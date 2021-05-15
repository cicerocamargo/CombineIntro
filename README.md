# A Combine introduction

Have you ever tried to learn reactive programming and got even more confused than before after reading some definitions of it? Yeah, I know. I've been there too and I promise won’t throw any definition at you here. What I want to do instead is using concepts that you already know and then show how to convert them into Combine code.

So let’s cut the bullshit and get started!

## Our case study

For us to have a realistic starting point imagine the following: you need to implement a component for a banking application that loads and presents the user's account balance. Here are some more detailed specifications:

* It must refresh each time it appears on-screen;
* It must provide a way for the user to refresh the balance manually;
* Currency should be formatted to USD;
* Once we have a value to show, we should always show the date when that value was acquired;
* It should redact the value when the app is not active;

The result looks like this:

![](https://github.com/cicerocamargo/CombineIntro/raw/main/recording.mp4)

I went ahead and implemented it in the simplest possible way that I could unit-test. Our starting point will be [this commit](https://github.com/cicerocamargo/CombineIntro/tree/b624810c6a6820b2894e5549458bcf95446c1ab2).

It's a UIKit MVC component and all the behavior as well as the view updates take place into the `BalanceViewController`. `BalanceView` contains just some ugly view code and it exposes a couple of subviews for the ViewController to tweak as needed. I know, this is not ideal from the encapsulation point of view, but it will serve as a temporary way to remove this ugliness from the controller, bear with me. 

We also have the `BalanceService`, which abstracts away the request to get the current balance, and `BalanceViewState`, which groups all the properties that compose the state of the component as well as some extensions with presentation logic.

Take some time to study the code. Consider starting from `BalanceViewControllerTests`, where I tried to cover everything at once: how the controller interacts with the service in reaction to certain events and how it updates the view with formatted data. It's pretty impressive how much code we need to write to get this simple component done, isn't it?

OK. Ready? Let's move on.

## It all comes down asynchronous events

Object-Oriented software is about objects sending messages (or *events*) to each other and updating their state correctly upon the reception of the events that they implement or are interested in.

Let's analyze the following excerpt from `BalanceViewController`:

```
(...)

override func viewDidLoad() {
    super.viewDidLoad()

    rootView.refreshButton.addTarget(
        self,
        action: #selector(refreshBalance),
        for: .touchUpInside
    )

    notificationCenterTokens.append(
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self]_ in
            self?.state.isRedacted = true
        }
    )

    notificationCenterTokens.append(
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self]_ in
            self?.state.isRedacted = false
        }
    )
}

override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    refreshBalance()
}

@objc private func refreshBalance() {
    state.didFail = false
    state.isRefreshing = true
    service.refreshBalance { [weak self] result in
        self?.handleResult(result)
    }
}

(...)
```

First of all, any `UIViewController` subclass will automatically be *subscribed* to a ton of *events* from the framework whether it wants or not. These subclasses can append behavior to certain events just by overriding specific methods. In our case, when the `viewDidLoad` event occurs `BalanceViewController` subscribes itself to events from other *publishers*: `rootView.refreshButton` and `NotificationCenter.default`.

In case it wanted to *cancel* these *subscriptions*, all it had to do is:

```
rootView.refreshButton.removeTarget(
    self,
    action: #selector(refreshBalance),
    for: .touchUpInside
)
notificationCenterTokens.forEach { token in
    NotificationCenter.default.removeObserver(token)
}
```

`BalanceViewController` also reacts to the `viewDidAppear` event by updating its state in preparation to refresh the balance, and sends an event (by a direct method call) to the `service` to fire a new request, passing a closure that should be invoked in reaction to the response being received.

I highlighted terms like *event*, *publisher*, *subscribe* and *cancel subscription* on purpose, firstly because they are frequent terms in Combine's dialect, but I also wanted to show you that you already understand event-driven programming and use it everyday. We just saw 3 manifestations of these concepts that are extensively used in UIKit: framework class/method overrides, the target-action pattern and closures (a.k.a. callbacks or blocks). 

The same applies to most of the *delegates* that you certainly have used, like when you have a `UITableView` and you set a custom class of yours as the `UITableViewDelegate`.
Your class will then be *reactive* to events, like the selection of a row at a given index, that happen in that table view.

[KVO](https://developer.apple.com/documentation/swift/cocoa_design_patterns/using_key-value_observing_in_swift) is another good example: you connect some code as a reaction to value changes of a property in some object. By the way, KVO calls can be converted into combine code directly, check [here](https://developer.apple.com/documentation/combine/performing-key-value-observing-with-combine) fore more details.

And the list goes on. But, as you see, nothing is really new. Combine and other reactive frameworks just propose another way to model this event publisher-subscriber relationship.

So why having yet another way to do the same stuff? 

Because reactive frameworks takes event handling to another level. The way Combine (and other frameworks like RxSwift or ReactiveCocoa) implements these mechanisms unlocks a lot of other useful features, as we're gonna see later.

For now let's just start “combinifying” the examples above (sorry for the long intro).

## The publisher side

We'll start with the `refreshButton` in `BalanceView`. I’ll adapt the target-action to a Combine publisher that propagates the `.touchUpInside` events by creating a subclass of UIButton, like this:

```
class CustomButton: UIButton {
    private lazy var touchUpInsideSubject: PassthroughSubject<Void, Never> = {
        let subject = PassthroughSubject<Void, Never>()
        addTarget(self, action: #selector(handleTap), for: .touchUpInside)
        return subject
    }()

    @objc private func handleTap(sender: UIButton, event: UIEvent) {
        touchUpInsideSubject.send()
    }

    var touchUpInsidePublisher: AnyPublisher<Void, Never> {
        touchUpInsideSubject.eraseToAnyPublisher()
    }
}
```

We could do this without subclassing, which would be better, but its a bit more complex and the code above is perfect to explain some new Combine types that appeared on the listing.

### AnyPublisher

The part that is visible to the outside is `touchUpInsidePublisher`, whose type is `AnyPublisher<Void, Never>`. This var exposes the upstream publisher (`touchUpInsideSubject `) in a read-only way by wrapping it in a type-erased Publisher. I won’t explain *type-erasure* here, but [here](https://www.bignerdranch.com/blog/breaking-down-type-erasure-in-swift/) is an excellent article on the topic. If you are not familiar with type erasure you can also read it later and just accept that it’s a necessary evil for the time being. 

Looking at the generic types (those types inside the angle brackets), the first one means that this publisher sends `Void` events (we could send the `UIEvent` instead but it's rarely useful, so let's stick with `Void`). The second one is the failure type, so `Never` is a Foundation type that can't be instantiated, meaning that this publisher can't fail, what makes sense since the UIButton will never break and stop sending touches.

### PassthroughSubject

The `touchUpInsideSubject` is the real meat here. `Subject`s are special types of publishers, that allow you to programatically send events. `PassthroughSubject`, as it name suggests, doesn’t store any event/value that you send. Events just "pass through" the subject and reach any subscribers that it might have **at that moment**. This is important: if you subscribe to this subject (or to any publisher built on top of it, like its type-erased version `touchUpInsidePublisher`) after a given event happened you’ll never receive it again. Save that information.

Less importantly, `touchUpInsideSubject` is intentionally structured as a lazy var, so that when it’s first needed, the button also adds itself as target to call `send` on the subject when a `UIControl.Event.touchUpInside` occurs.

## The subscriber side

Now let's see how we can update `BalanceViewController` to use our new button subclass and subscribe to `touchUpInsidePublisher`.

```
import Combine
(...)

class BalanceViewController: UIViewController {
    private var buttonCancellable: AnyCancellable?
	(...)

    override func viewDidLoad() {
        super.viewDidLoad()

        buttonCancellable = rootView.refreshButton.touchUpInsidePublisher
            .sink(
                receiveValue: { [weak self] _ in
                    self?.refreshBalance()
                }
            )
            
        (...)
    }
    
    (...)
    
    private func refreshBalance() { (...) }
}
```

Setting up a tap handler is a lot simpler now and we also don't need `@objc` functions anymore. It can get even simpler if we use the trailing closure syntax in the `sink` call:

```
buttonCancellable = rootView.refreshButton.touchUpInsidePublisher
    .sink { [weak self] _ in
        self?.refreshBalance()
    }
```

We run the tests and they still pass. Nice!

But while we improved the code slightly we also had to add the `buttonCancellable` var, so let me explain all these new stuff before we move on.

### Sink

The simplest way of creating a subscription to a publisher is to call `sink` passing a `receiveValue` closure that will be called on each new event. The input parameter is that `Void` value that we sent from the subject inside `CustomButton`. It doesn't contain any information, so we can just ignore it.

If we were interested in knowing when this publisher stops sending events, either because it completed successfuly or because it failed (which can't happen because the failure type is `Never`), we would also have to pass a `receiveCompletion` closure. As this is not the case let's not bother with this now.

### AnyCancellable

So, from now on everytime this publisher sends an event (i.e. the button is tapped) `receiveValue` closure will be called. Well, not so fast. A crucial part is to retain the return value of `sink`, which is an instance of `AnyCancellable` (hello again *type erasure*). The cancellable object is what will ultimately keep this subscription alive, until you explicitly call `cancel` on it or the object is deallocated. In our example only `BalanceViewController` has a strong reference to `buttonCancellable`, so both will die together and the subscription will be cancelled at a proper time.

Just be careful with retain cycles because everything that you reference strongly in the `sink` closures will be indirectly referenced by the cancellable too.

Here's the full [diff](https://github.com/cicerocamargo/CombineIntro/compare/b624810c6a6820b2894e5549458bcf95446c1ab2...20021065822fe5d4d996e78be42a6edd4d17ec63) from our starting point.

## What about NotificationCenter?

`NotificationCenter` already provides extensions that allow for creating publishers for a given `Notification.Name`, so `BalanceViewController` can be updated like this:

```
class BalanceViewController: UIViewController {
    (...)
    private var appWillResignActiveCancellable: AnyCancellable?
    private var appDidBecomeActiveCancellable: AnyCancellable?

    (...)

    override func viewDidLoad() {
        (...)

        appWillResignActiveCancellable = NotificationCenter.default
            .publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                self?.state.isRedacted = true
            }

        appDidBecomeActiveCancellable = NotificationCenter.default
            .publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.state.isRedacted = false
            }
    }
    
    (...)
}
```

Now the input parameter of the `receiveValue` closures will be the `Notification` objects, which I'm not interested in as well. But the point here is that the type of this input value is always bound to the generic type from the publisher.

Some things are not visible in the code above: I got rid of the `notificationCenterTokens` var and could also delete the custom `deinit` because the cancellables will already take care of the unsubscribe. On the other hand, I had to add 2 new `AnyCancellable` vars to retain the subscriptions. This is starting to smell...

As all the 3 cancellables have the same lifetime (they should live while their instance of `BalanceViewController` exists), we can put all of them into a signle `Set` and use a convenient `store(in:)` function to throw them in there immediately after their creation. Let's see how this looks:

```
class BalanceViewController: UIViewController {
    private var cancellables: Set<AnyCancellable> = []

    (...)

    override func viewDidLoad() {
        super.viewDidLoad()

        rootView.refreshButton.touchUpInsidePublisher
            .sink { [weak self] _ in
                self?.refreshBalance()
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                self?.state.isRedacted = true
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.state.isRedacted = false
            }
            .store(in: &cancellables)
    }
    
    (...)
}
```

Neat, right? Tests still pass. Here is the [whole change](https://github.com/cicerocamargo/CombineIntro/compare/20021065822fe5d4d996e78be42a6edd4d17ec63...b18a1aed2fb471aa1a55b7e9672faa63e543e922). Moving on.

## Next

This is a living document, so I'll be updating it as I progress with the next concepts and refactors.

You can start watching the repo and follow me on [twitter](https://twitter.com/cicerocamargo) for updates.

If you have suggestions, corrections, etc., feel free to open a Pull Request or send me a message.
