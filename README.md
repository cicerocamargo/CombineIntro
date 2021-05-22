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

![](https://github.com/cicerocamargo/CombineIntro/raw/main/recording.gif)

I went ahead and implemented it in the simplest possible way that I could unit-test. Our starting point will be [this commit](https://github.com/cicerocamargo/CombineIntro/tree/b624810c6a6820b2894e5549458bcf95446c1ab2).

It's a UIKit MVC component and all the behavior as well as the view updates take place into the `BalanceViewController`. `BalanceView` contains just some ugly view code and it exposes a couple of subviews for the ViewController to tweak as needed. I know, this is not ideal from the encapsulation point of view, but it will serve as a temporary way to remove this ugliness from the controller, bear with me. 

We also have the `BalanceService`, which abstracts away the request to get the current balance, and `BalanceViewState`, which groups all the properties that compose the state of the component as well as some extensions with presentation logic.

Take some time to study the code. Consider starting from `BalanceViewControllerTests`, where I tried to cover everything at once: how the controller interacts with the service in reaction to certain events and how it updates the view with formatted data. It's pretty impressive how much code we need to write to get this simple component done, isn't it?

OK. Ready? Let's move on.

## It all comes down to asynchronous events

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

## Observing updates from stored properties

In this section we're going to refactor our component towards the MVVM (Model-View-ViewModel) pattern, and by doing that we'll learn how we can use Combine to observe updates from stored properties.

### Refactoring to MVVM

Before we start changing the code, let's talk about the role of the `ViewModel`. Comparing our component to a living organism, I see the `ViewModel` as the **brain**, where the the `View/ViewController` is the body. The role of the brain is to tell the body how to behave and how it feels at the moment, while the body reacts to that state of the brain and also sends signals, as this being interacts with the environment, for the brain to process. Also, if the organism is too simple there's no need for a complex brain, a pretty dumb one is enough for the body to fill its role in the environment.

Translating this into developer words, the `View/ViewController` is the body and the `ViewModel` is the brain. If the component is too dumb, one without any complex/asynchronous behavior, the `ViewModel` *is* the state that feeds the view and can be modeled as a value type (`struct` or `enum`). Now, if the component contains behavior (which is the case for our Balance component) the `ViewModel` will encapsulate this behavior by (1) providing an **observable** state for the `View/ViewController` to render and (2) handling any events that the `View/ViewController` might send. The role of the view layer is just **binding** correctly to the ViewModel, so that its always sends the right events and renders the `ViewModel`'s current state.

So we'll start by defining a class that will own the state of our `BalanceViewController` and then we'll move all the behavior and state updates into this class.

```
import Combine
import Foundation
import UIKit

final class BalanceViewModel {
    private(set) var state = BalanceViewState()
    private let service: BalanceService
    private var cancellables: Set<AnyCancellable> = []

    init(service: BalanceService) {
        self.service = service

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

    func refreshBalance() {
        state.didFail = false
        state.isRefreshing = true
        service.refreshBalance { [weak self] result in
            self?.handleResult(result)
        }
    }

    private func handleResult(_ result: Result<BalanceResponse, Error>) {
        state.isRefreshing = false
        do {
            state.lastResponse = try result.get()
        } catch {
            state.didFail = true
        }
    }
}
```

You may have wrinkled your nose to that `import UIKit` at the top because I'm adding a framework dependency to my `ViewModel` and that will make it harder to reuse this component in that WatchOS app that some customers have been asking for... Yes, I could have done this is a number of ways but I don't want to overcomplicate things here and I really wanted to extract these subscriptions from `BalanceViewController`, so that in the future we can replace it with a SwfitUI view with minimal effort, so bear with me.

Let's return to our `BalanceViewController`, which is completely broken, at this point. After some adjustments, this is what I got:

```
class BalanceViewController: UIViewController {
    private let rootView = BalanceView()
    private let viewModel: BalanceViewModel
    private let formatDate: (Date) -> String
    private var cancellables: Set<AnyCancellable> = []
    
    init(
        service: BalanceService,
        formatDate: @escaping (Date) -> String = BalanceViewState.relativeDateFormatter.string(from:)
    ) {
        self.viewModel = .init(service: service)
        self.formatDate = formatDate
        super.init(nibName: nil, bundle: nil)
    }

    (...)    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        rootView.refreshButton.touchUpInsidePublisher
            .sink(receiveValue: viewModel.refreshBalance)
            .store(in: &cancellables)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewModel.refreshBalance()
    }
    
    private func updateView() {
        rootView.refreshButton.isHidden = viewModel.state.isRefreshing
        if viewModel.state.isRefreshing {
            rootView.activityIndicator.startAnimating()
        } else {
            rootView.activityIndicator.stopAnimating()
        }
        rootView.valueLabel.text = viewModel.state.formattedBalance
        rootView.valueLabel.alpha = viewModel.state.isRedacted
            ? BalanceView.alphaForRedactedValueLabel
            : 1
        rootView.infoLabel.text = viewModel.state.infoText(formatDate: formatDate)
        rootView.infoLabel.textColor = viewModel.state.infoColor
        rootView.redactedOverlay.isHidden = !viewModel.state.isRedacted
    }
}

```

Looks much shorter now, right? And pay attention to how we simplified that `sink` call on `viewDidLoad()`. As the `receiveValue` closure has a `Void` input argument and `func refreshBalance()` also receives no arguments, I can forward the event directly to the `ViewModel`, there's no need to go through `self` anymore. Just be careful when using this as it will keep a strong reference from the cancellable to the `viewModel`, which is fine as long as the `viewModel` doesn't have a strong reference back to the `ViewController`, which will ultimately own the cancellable.

Let's run our tests again and... oops! Almost all off them failed. That's because `updateView()` is not being called anymore when the state is updated by the `ViewModel`. How could the `ViewController` know about that?

Maybe the `ViewController` could set up a closure for the `ViewModel` to call back every time the state changes, or maybe we could have a delegate protocol between them, or maybe KVO... No, no, no. All of them would work, but we're here to learn Combine. Not just because it's the subject of the article, but because it's better for a numbebr of reasons: we don't need to have `weak` references, we can have multiple subscribers, we unlock a lot of useful operators, `ViewModel` doesn't need to inherit from `NSObject`...

So, what our `ViewController` needs is that the `ViewModel` provides a publisher that will send events back every time the state changes. So, based on what we learned in [Part 1](https://cicerocamargo.github.io/articles/combine-intro-1/), you may have thought about this:

```
final class BalanceViewModel {
    private let stateSubject = PassthroughSubject<BalanceViewState, Never>()
    private(set) var state = BalanceViewState() {
        didSet {
            stateSubject.send(state)
        }
    }
    var statePublisher: AnyPublisher<BalanceViewState, Never> {
        stateSubject.eraseToAnyPublisher()
    }
    
    (...)
```

Ok, this will work for our use case as the state is updated right after the component appears. If this wasn't the case, the `ViewController` would have to make an additional call, along with the subscription, to render the initial state. This is not ideal, so let me introduce to you `CurrentValueSubject`.

### CurrentValueSubject

This is a subject that stores a value and also publishes changes on it, so that subscribers get the current value right away when they subscribe and also any subsequent updates. Let's see how we could fix our current issue using a `CurrentValueSubject`.

```
final class BalanceViewModel {
    private let stateSubject: CurrentValueSubject<BalanceViewState, Never>
    private(set) var state: BalanceViewState {
        get { stateSubject.value }
        set { stateSubject.send(newValue) }
    }
    var statePublisher: AnyPublisher<BalanceViewState, Never> {
        stateSubject.eraseToAnyPublisher()
    }
    
    (...)
    
    init(service: BalanceService) {
        self.service = service
        stateSubject = .init(BalanceViewState())
        
        (...)
    }
    
    (...)
}
```

Since `stateSubject` already stores a `BalanceViewState` it has become our source of truth, and `state` has become just a proxy to get the current value from `stateSubject` and push changes to `stateSubject` through a `send` call. Just be careful that everytime we change any property under `BalanceViewState`, a new state is published to the subscribers. This is happenning in our code as we change the state properties in place, one by one, instead of making a copy of the state, changing all the properties we need, and then writing the new value back to `self.state` again. It's not a big deal for our simple example, just be aware of this.

Also, similarly to what we've done in our `CustomButton`, we don't want to expose the subject itself because only `BalanceViewModel` should be able to call `send` on it, so we're providing it to the external world as an `AnyPublisher`. 

Now back to `BalanceViewController`, all we need to do is adding the following after `super.viewDidLoad()`:

```
viewModel.statePublisher
    .sink { [weak self] _ in self?.updateView() }
    .store(in: &cancellables)
```

We can just ignore the input value for now because we are already accessing it directly in the viewModel inside `func updateView()`. 

It's time to run our tests again. They all pass! Yay! You can see the full diff [here](https://github.com/cicerocamargo/CombineIntro/compare/f94da3262867c551ba6c7665f82516ed617755c1...752a7f9d0c046e6f8337c2ca0396601ca8a430ce).

### @Published

Once you start using `CurrentValueSubject` you'll find yourself repeating the same pattern again and again: the subject is the source of truth, you have a var to access it in a more convenient way, and you also have to expose it to subscribers as a read-only publisher. Maybe we could write a property-wrapper to encapsulate all this...

I have good news: it already exists! If you have played with SwiftUI you might also have used the @Published property-wrapper. Let's see how we can use it in our UIKit app.

All we have to do in `BalanceViewModel` is replacing those 3 members (`stateSubject`, `statePublisher` and that proxy `state` var) with:

```
@Published private(set) var state = BalanceViewState()
```

It always reads a bit funny to me because it's "published" (which sounds like it's `public`) but it's also "private" at the same time. Anyway, this is exactly what we need: a value that can only be written by it's owner (`BalanceViewModel`) but can be read and observed from the outside. 

Now we have to adjust the `ViewController`. All we need to do is changing where we were accessing `viewModel.statePublisher` to `viewModel.$state` that we'll have access to the publisher that comes with this property wrapper.

We run our tests again and... they fail! WTF?!

Well, we are ignoring the value that comes from the publisher and reaching the ViewModel again to get the current state. The problem is that `@Published` publishes the new value on the `willSet` of the property it wraps, so at the time the subscribers receive the new value the source of truth hasn't been written yet. This works seamlessly in SwiftUI because the framework does all the magic and recalculates the View's body at the right moment, but in our case if we want to use `@Published` we can't ignore the value, so let's update our `BalanceViewController` and start using the state from the publisher instead of reaching the `viewModel` again on `updateView`:


```
class BalanceViewController: UIViewController {
    (...)
    
    override func viewDidLoad() {
        super.viewDidLoad()

        viewModel.$state
            .sink { [weak self] in self?.updateView(state: $0) }
            .store(in: &cancellables)
        
        (...)
    }
    
    (...)
    
    private func updateView(state: BalanceViewState) {
        rootView.refreshButton.isHidden = state.isRefreshing
        if state.isRefreshing {
            rootView.activityIndicator.startAnimating()
        } else {
            rootView.activityIndicator.stopAnimating()
        }
        rootView.valueLabel.text = state.formattedBalance
        rootView.valueLabel.alpha = state.isRedacted
            ? BalanceView.alphaForRedactedValueLabel
            : 1
        rootView.infoLabel.text = state.infoText(formatDate: formatDate)
        rootView.infoLabel.textColor = state.infoColor
        rootView.redactedOverlay.isHidden = !state.isRedacted
    }
}
```

And our tests are back to green. [Here](https://github.com/cicerocamargo/CombineIntro/commit/cd9dbd1ea2660ad84d5a865c26259a3ab918e26e)'s the full change.

## Next

This is a living document, so I'll be updating it as I progress with the next concepts and refactors.

You can start watching the repo and follow me on [Twitter](https://twitter.com/cicerocamargo) or [LinkedIn](https://www.linkedin.com/in/cicerocamargo/) to be notified about updates.

If you have suggestions, corrections, etc., feel free to open a Pull Request or send me a message.
