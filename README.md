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

## Other ways of creating subscriptions

In this section we're refactoring our component even further and along the way we're gonna learn 2 new subscription mechanisms: **Subscribe** and **Assign**.

### Subscribe

One thing that I don't like in our code at the moment is that the `ViewController` is not exactly sending *events* do the `ViewModel`, but giving it *commands* instead. In other words, when the button is tapped `ViewController` doesn't say *"hey ViewModel, the refresh button was tapped, you may want to do something about it now..."*. No, it tells the ViewModel exatcly what to do: *"Refresh the balance!"*. The same applies to `viewDidAppear`. 

This difference is subtle, but it matters and we're gonna fix this now. The first thing we're going to do is creating an `enum` to contain all events that flow from `BalanceViewController` to `BalanceViewModel`:

```
enum BalanceViewEvent {
    case viewDidAppear
    case refreshButtonWasTapped
}
```

The next step is creating a subject in `BalanceViewModel` that will receive all the external events, and make a private subscription to it using `sink`:

```
final class BalanceViewModel {
    let eventSubject = PassthroughSubject<BalanceViewEvent, Never>()
    (...)
    
    init(service: BalanceService) {
        (...)
        
        eventSubject
            .sink { [weak self] in self?.handleEvent($0) }
            .store(in: &cancellables)
    }

    private func handleEvent(_ event: BalanceViewEvent) {
        switch event {
        case .refreshButtonWasTapped, .viewDidAppear:
            refreshBalance()
        }
    }

    private func refreshBalance() {
        (...)
    }

    (...)
}
```

With this change we could make `refreshBalance()` private because, again, we don't want anybody telling our *ViewModel* what to do. The only thing an external caller
can do with our `ViewModel` now is sendind it a `BalanceViewEvent` through the `eventSubject` and reading or subscribing to the `ViewModel`'s state.  

Now we need to update the `ViewControler`. In `viewDidAppear` we just change `viewModel.refreshBalance()` for `viewModel.eventSubject.send(.viewDidAppear)`. In `viewDidLoad` is where we're gonna do it differently: we'll replace that `sink` on `rootView.refreshButton.touchUpInsidePublisher` with the following:

```
rootView.refreshButton.touchUpInsidePublisher
    .map { _ in BalanceViewEvent.refreshButtonWasTapped }
    .subscribe(viewModel.eventSubject)
    .store(in: &cancellables)
```

In the listing above we first append a `map` operator so that every time the button sends us that `Void` touch event we transform it into a proper `BalanceViewEvent`, which is the type of event that `eventSubject` accepts. Then we call `subscribe(viewModel.eventSubject)` on the resulting publisher, and retain the cancellable (as we were doing before). 

From now on, every button tap will be transformed into a `BalanceViewEvent.refreshButtonWasTapped` and this event flow directly into `eventSubject`, and our `ViewModel` will, of course, be listening to all the events that pass through `eventSubject`.

Time to run our tests again. They pass. Here's the [commit](https://github.com/cicerocamargo/CombineIntro/commit/16572300c2df3de5d556492f1bf87bb06c5c6bd3) with the change.

#### Is replacing functions with subjects worth it?

Before we move on, I wanted to analyze what we did on the `ViewModel`. Besides the mental shift from commands to events, we replaced function calls (we had only one in our simple example, but we usually have more than that) with a single subject, where the `ViewModel` can receive all the events it knows how to handle. This change looks a bit overkill for our tiny app, but they bring interesting capabilities to our code.

First, now that our ViewModel has a single point for receiveing events and a single var to store and publish the current state, we're very close to having a generic definition that we could use for *any* `ViewModel`, and this could even be used to decouple the `ViewController` from the `ViewModel` as long as they work with the same type for the events and for the state. But that's subject for another article.

Second, the fact that we're receiving events through a subject allows the viewModel to apply operators to different events. Imagine that we should only refresh the balance on the first time the view appears. We could do this without any additional var to control the number of times the "view did appear", the only thing we need to do is use the `first(where:)` operator:


```
eventSubject
    .first(where: { $0 == .viewDidAppear })
    .sink { [weak self] _ in self?.refreshBalance() }
    .store(in: &cancellables)
```

You can argue that I could also change the `viewDidAppear` event to a `viewDidLoad` event, and you're right, but if you switch to SwiftUI, for instance, you only have the `onAppear` event and it can be called multiple times, so if you have a requirement like this (refreshing automatically *only in the first time* the view appears) with a SwiftUI View you'll end up having to do something like we did above.

Another example: imagine that our *BalanceViewController* is a child of a larger *ViewController* that will show a lot of other things like last transactions the user made; as the user is new to the app, this parent `ViewController` is showing a text overlay explaining the balance widget and inviting the user to tap into the refresh balance button. When the user taps on it, in addition to refreshing the balance, the overlay should be dismissed. Well, anyone that knows our ViewModel can use `eventSubject` to send events to it,  right? But they can also subscribe to this subject and also be notified when the ViewModel *receives* events from any source. This way our outer `ViewController` can know when the refresh button was tapped without the need for any additional `NSNotification`, callback or anything.

So, again, I'm not doing these changes just to push it with Combine. I really think modeling the inteface of my ViewModel in this way has several benefits.

### Assign

The last subscription mechanism that I want to show today is the `.assign(to:on:)` function.

So far, we're binding the state updates to the view updates with the following piece of code in our `BalanceViewController`:

```
override func viewDidLoad() {
    super.viewDidLoad()

    viewModel.$state
        .sink { [weak self] in self?.updateView(state: $0) }
        .store(in: &cancellables)
    
    (...)
}

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

```

By doing that we always update everything regardless of what changed from the past value of `viewModel.state`. To give you and example, if only `state.isRefreshing` changed the only views that should really be updated are `rootView.refreshButton` and `rootView.activityIndicator`, but in our case we're also changing texts, alphas, colors, etc., anyway.

So let's extract the updates to `rootView.refreshButton` and `rootView.activityIndicator` from this generic flow to more specific subscriptions. I'll start with `rootView.refreshButton` by removing the first line in the `updateView(state:)` function and addding the following to `viewDidLoad()`:

```
let isRefreshingPublisher = viewModel.$state
    .map(\.isRefreshing)
    .removeDuplicates()

isRefreshingPublisher
    .assign(to: \.isHidden, on: rootView.refreshButton)
    .store(in: &cancellables)
```

On the first three lines I take the `$state` publisher from the `viewModel` and use the `map()` operator with a *key path* to derive another publisher that extracts just the `Bool` value of `isRefreshing` from the whole `BalanceViewState` struct. If you don't understand what key paths are is I suggest that you read [this article](https://www.swiftbysundell.com/articles/the-power-of-key-paths-in-swift/) from John Sundell.

Continuing, if I stop here and create a subscription to `viewModel.$state.map(\.isRefreshing)` I'll still be receiving repeated values. For instance, if the current value of the state has `isRefreshing` equal to `false` and the user answers a phone call, this will make the app inactive and `state.isRedacted` will be set to `true`. This change, which has nothing to do with `isRefreshing`, will generate another value for the whole `state` struct and `viewModel.$state.map(\.isRefreshing)` will ping me back with another `false` value, which is the value for `isRefreshing` in this new `state`. To prevent the reception of duplicated values, we can append the `.removeDuplicates()` operator. This operator will wrap the publisher resulting from the `map` call and only propagate values to the subscribers when they really changed.

Let's stop and take a look at the type of the `isRefreshingPublisher`:

`Publishers.RemoveDuplicates<Publishers.MapKeyPath<Published<BalanceViewState>.Publisher, Bool>>`

This is a pure application of the [decorator pattern](https://refactoring.guru/design-patterns/decorator) in a heavily generic API, but it reads so complicated (and here we only applied 2 operators) that this is why we always prefer erasing to `AnyPublisher` when we need to declare the type of the publisher explicitly. The really important part of this type is that `Bool` at the end. We derived this publisher from a key path of a `Bool` property and that's the type of value that we'll get back when we subscribe to this publisher.

Talking about subscription, let's analyze that `assign(to:on:)` call, which effectively creates the subscription. The first parameter is a writable key path and the second parameter is the class that contains this key path. The type of the variable pointed by this key path must match the type of the publisher's value (that `Bool` we emphasized before). Just like `sink`, `assign` returns a `AnyCancellable` that must be stored while we want to keep the subscription alive.

The effect of this subscription is that every time `isRefreshingPublisher` publishes a new value it's instanteneously *assigned* to `isHidden` on `rootView.refreshButton`, which is exactly what we want. 

A second implication is that the subscription creates a strong refefrence to the object passed as the second parameter, which is fine as `rootView.refreshButton` doesn't hold any strong reference back to our ViewController, the owner of the cancellable. We could also write the same subscription targeting the `rootView` instead:

```
isRefreshingPublisher
    .assign(to: \.refreshButton.isHidden, on: rootView)
    .store(in: &cancellables)
```

This would also work fine. However, we would be creating a retain cycle with the following code:

```
isRefreshingPublisher
    .assign(to: \.rootView.refreshButton.isHidden, on: self)
    .store(in: &cancellables)
```

Whenever you need to assign to key paths on `self` prefer using `sink { [weak self] value in }` instead or call `.assign(to: (...), onWeak: self)` using the following extension:

```
extension Publisher where Failure == Never {
    func assign<Root: AnyObject>(
        to keyPath: ReferenceWritableKeyPath<Root, Output>,
        onWeak object: Root
    ) -> AnyCancellable {
        sink { [weak object] value in
            object?[keyPath: keyPath] = value
        }
    }
}
```

Moving on, this is how our `updateView(state:)` function looks like at the moment:

```
private func updateView(state: BalanceViewState) {
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
```

As we mentioned before, `state.isRefreshing` also controls the animation of the `rootView.activityIndicator`, so let's replace this if-else on `updateView(state:)` with another subscription to `isRefreshingPublisher` in `viewDidLoad()`:

```
isRefreshingPublisher
    .assign(to: \.isAnimating, on: rootView.activityIndicator)
    .store(in: &cancellables)
```

But the compiler yells at us with an error that reads very complicated because of the deeply nested generics from `isRefreshingPublisher`:

```
Key path value type 'ReferenceWritableKeyPath<UIActivityIndicatorView, Publishers.RemoveDuplicates<Publishers.MapKeyPath<Published<BalanceViewState>.Publisher, Bool>>.Output>' (aka 'ReferenceWritableKeyPath<UIActivityIndicatorView, Bool>') cannot be converted to contextual type 'KeyPath<UIActivityIndicatorView, Publishers.RemoveDuplicates<Publishers.MapKeyPath<Published<BalanceViewState>.Publisher, Bool>>.Output>' (aka 'KeyPath<UIActivityIndicatorView, Bool>')
```

Don't be intimidated. Those "aka"s actually help a lot. The problem is that `isAnimating` is a readonly property on `UIActivityIndicatorView` and we obviously can't have a writable keypath from a readonly property. So we either need to go back to using a `sink` or find another way to use `assign`. I'll go with the second option, by creating the following extension:

```
extension UIActivityIndicatorView {
    var writableIsAnimating: Bool {
        get { isAnimating }
        set {
            if newValue {
                startAnimating()
            } else {
                stopAnimating()
            }
        }
    }
}
```

Now all we need to do is replacing that `\.isAnimating` key path with `\.writableIsAnimating` and run the tests again. Here is the [commit diff](https://github.com/cicerocamargo/CombineIntro/commit/d48d8645689abbd3907ae48e35dd99307f812a46).

You might be thinking that creating these fine-grained subscriptions for each subview that we need to update is overkill for our component.
And you are completely right. I went ahead and replaced every view update that we had in `BalanceViewController` with calls to `assign` after applying a couple of operators, [check it out](https://github.com/cicerocamargo/CombineIntro/commit/59194faa4142a91fdbd2072242ef145306dae8e9). 

Besides being unnecessarily precise (UIKit is optimized enough to know when some property update will really require a new render phase), this is much harder to read than our old `updateView(state:)` function, even after cleaning up all those `.store(in:)` calls.

I'm doing this for explanatory purposes, of course, but we usually work on more complex screens right? You'll probably spot better opportunities to use `assign` at a higher level as you start using Combine in your apps, specially with UIKit, so keep these mechanisms in mind and don't always chose `sink` without reflecting before if `assign` or `subscribe` could be applicable **AND** make your code better.

## Using combine to make requests

The only layer where we didn't use Combine so far is the Networking/Service layer, so let's change that now. The quickest way to accomplish that is using `Future` to adapt our callback-based `BalanceService ` API to return a publisher. Let's take a look.

### Future

`Future` is a special kind of `Publisher` that we can use to manually send a value asychronously, just like we did with `Subject`s, but we're only allowed to either send a single value and complete or fail (if you come from RxSwift, it's the same as `Single`). `Future` is perfect to adapt closure-based APIs to Combine, and I'll create an extension of our `BalanceService` protocol to show you exactly what I mean.

```
extension BalanceService {
    func refreshBalance() -> AnyPublisher<BalanceResponse, Error> {
        Future { promise in
            self.refreshBalance { result in
                do {
                    let response = try result.get()
                    promise(.success(response))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }
}
```

Our new version of `refreshBalance()` calls the old one inside a closure that `Future` receives on its constructor, where we can execute our asynchronous tasks. This closure also provides another closure as input, the `promise` parameter, and we should use that to call back when our asynchronous tasks are finished with a `Result` object indicating a success or a failure. In fact, the shape of the `promise` closure is exactly the same as the `completion` parameter in the original `refreshBalance` function, so we don't really need to unwrap the result, we can just forward `promise` like this:

```
extension BalanceService {
    func refreshBalance() -> AnyPublisher<BalanceResponse, Error> {
        Future { promise in
            self.refreshBalance(completion: promise)
        }
        .eraseToAnyPublisher()
    }
}
```

We could also return `Future<BalanceResponse, Error>` instead of an `AnyPublisher`, but that would leak some implementation details to the caller so I usually prefer erasing to `AnyPublisher`. 

Now we need to adjust `BalanceViewModel` to call the new version of `refreshBalance()`, and we'll do it by calling `sink` on the "erased" `Future`:

```
final class BalanceViewModel {
    (...)

    private func refreshBalance() {
        state.didFail = false
        state.isRefreshing = true
        service.refreshBalance()
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.state.isRefreshing = false
                    if case .failure = completion {
                        self?.state.didFail = true
                    }
                },
                receiveValue: { [weak self] value in
                    self?.state.lastResponse = value
                }
            )
            .store(in: &cancellables)
    }
}
```

This time we can't ignore the `receiveCompletion` closure because the Publisher's failure type is `Error` (instead of `Never`), so it can really fail.

I won't lie: this `sink` with two closures is pretty ugly and makes me remember the APIs from the old ObjC days, and even some from early versions of Swift, before we had the `Result` type (which I first saw in [Alamofire](https://github.com/Alamofire/Alamofire), long before we had an official version in the Foundation framework). On the other hand, this makes it clear to the caller that these two callbacks may not be called together, example: if we [prepend](https://developer.apple.com/documentation/combine/publisher/prepend(_:)-v9sb) a cached value synchronously then fire the request we'll have `receiveValue` called twice before `receiveCompletion`.

Let's run our tests to see if everything works. Tests pass. [Here](https://github.com/cicerocamargo/CombineIntro/commit/71ea1a3759352346ac82e55bf26539160baf91dc) is the full commit.

One thing that's missing here is the following: if the original `refreshBalance(completion:)` function would return some kind of cancellable token, we should cancel the original request manually as the subscriptions to our `Future` are cancelled. The way for us to receive that information from `Future` is appending a [handleEvents(receiveCancel: { ... })](https://developer.apple.com/documentation/combine/publisher/handleevents(receivesubscription:receiveoutput:receivecompletion:receivecancel:receiverequest:)) call before `eraseToAnyPublisher()`. However, the whole thing would be a bit more complicated than that and would go beyond the scope of this article, so I'll leave it as an exercise to the reader.

### URLSession extensions

Now we're gonna throw our `BalanceService` extension away and use Combine directly in the definition of the protocol to see what happens. This is our new `BalanceService` protocol.

```
protocol BalanceService {
    func refreshBalance() -> AnyPublisher<BalanceResponse, Error>
}
```

I'll also get rid of the `FakeBalanceService` and implement a live version, which makes a real request to fetch this JSON [here](https://api.jsonbin.io/b/60b76b002d9ed65a6a7d6980) and parses the reponse data to a `BalanceResponse`. For that I'll use the Combine extensions that come with `URLSession`, but you can choose your preferred one. Good networking libraries like [Alamofire](https://github.com/Alamofire/Alamofire) will provide built-in support for Combine.

We'll start by making `BalanceResponse` a `Decodable` type and updating `App Transport Security Settings` in my info plist to allow arbitrary loads. Then we implement the live service like this:

```
struct LiveBalanceService: BalanceService {
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        decoder.dateDecodingStrategy = .formatted(dateFormatter)
        return decoder
    }()

    private let url = URL(
        string: "https://api.jsonbin.io/b/60b76b002d9ed65a6a7d6980"
    )!

    func refreshBalance() -> AnyPublisher<BalanceResponse, Error> {
        URLSession.shared
            .dataTaskPublisher(for: url) // 1
            .tryMap { output -> Data in // 2
                guard let httpResponse = output.response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                return output.data
            }
            .decode(type: BalanceResponse.self, decoder: decoder) // 3
            .receive(on: DispatchQueue.main) // 4
            .eraseToAnyPublisher() // 5
    }
}
```

Starting from the `refreshBalance()` function:

1. We use the `dataTaskPublisher(for url: URL)` extension from `URLSession` to make a simple `GET` request; if we needed to do a custom request we would use `dataTaskPublisher(for request: URLRequest)` instead;
2. When the request returns we check its output (of type `URLSession.DataTaskPublisher.Output`) to validate the response status code, and if it's OK we propagate the `Data`;
3. We decode the response `Data` to a `BalanceResponse` using a custom `JSONDecoder` that knows how to convert `"2021-06-02 11:01:48 +0000"` into a `Date` object;
4. As `URLSession.shared` works on its own queue, we use `receive(on:)` to dispatch the `BalanceResponse` to the main queue before it reaches our ViewModel, which will generate the UI updates and must do that on the main queue;
5. Last, we erase the resulting publisher to `AnyPublisher`, otherwise we would have a huge return type (as we saw in the previous articles), and that would have to leak to the protocol;

About step 4, we could have done the async dispatch inside our ViewModel too but then we would have asynchronous code in our tests. Furthermore threading is a [cross-cutting concern](https://en.wikipedia.org/wiki/Cross-cutting_concern) and we can apply other design patterns to solve that in a way that our business logic doesn't have to know about threads. I'll make sure I come back to this in another article.

Now we need to replace all the places where we were using `FakeBalanceService` to use `LiveBalanceService`. This will include the `BalanceViewController` previews which is not ideal, but we'll return to this soon. After some tweaks we get the project compiling again and we can see our live service in action. 

The test target, however, still need adjustments. I usually fix the tests before comitting the changes but this time I'll commit the current state as it is so that you can take a look at the [diff](https://github.com/cicerocamargo/CombineIntro/commit/bd9c234118957f41946490ef1d9ffa9d5d334db4).

### Synchronous Publishers

It's time to fix our `BalanceServiceStub` so that it conforms to `BalanceService` again. Let's recap how it looks at the moment:

```
class BalanceServiceStub: BalanceService {
    private(set) var refreshCount = 0
    var result: Result<BalanceResponse, Error>?

    func refreshBalance(
        completion: @escaping (Result<BalanceResponse, Error>) -> Void
    ) {
        refreshCount += 1
        if let result = result {
            completion(result)
        }
    }
}
```

When we need to test scenarios where the service returns some response, we set that `result` variable to `.success(BalanceResponse(...))` so that when `refreshBalance` is called we call `completion` synchronously with the stubbed result. We can also set `result` to `.failure(...)` when we want to test failure scenarios, or set it to `nil/.none` when we want to check the system state when it's waiting for the response.

Well, now that we know how `Future` works we could be lazy and add that same function to `BalanceServiceStub` to fix everything:

```
func refreshBalance() -> AnyPublisher<BalanceResponse, Error> {
    Future { promise in
        self.refreshBalance(completion: promise)
    }
    .eraseToAnyPublisher()
}
```

As `completion` is always called synchronously this works, but I want to take another path and show you other useful `Publisher`s. This is how we're gonna implement `refreshBalance`:

```
func refreshBalance() -> AnyPublisher<BalanceResponse, Error> {
    refreshCount += 1

    switch result {
    case .failure(let error):
        return Fail(outputType: BalanceResponse.self, failure: error)
            .eraseToAnyPublisher()

    case .success(let response):
        return Just(response)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()

    case .none:
        return Empty(completeImmediately: false)
            .eraseToAnyPublisher()
    }
}
```

Let's analyze them from the perspective of the subscriber:

1. `Just` sends its value and completes successfully, everything happening synchronously when you `sink` to it; we also need to set an appropriate failure type here, because `Just` has a `Never` failure type by default;  
2. `Fail` will also complete immediately with a `failure` completion containing the `error` and won't send any value;
3. `Empty` will never send any value too but will complete immediately with `.success` unless we create it with `completeImmediately: false`, in this case it'll never complete as well.

With our `BalanceServiceStub` fixed we can run the tests again. They pass. [Commit](https://github.com/cicerocamargo/CombineIntro/commit/334463a3f901eeeb0307e4acae825386cf9264cf) and push. We're done!

## Final thougths

By constantly refactoring this simple app we could explore a lot of ways to "Combinify" existing applications, and really hope this process helped you understand the fundamentals of the framework and also to think in a reactive way.

I'll certainly write more Combine in the future to explore different ways to compose publishers, advanced operators, back pressure, etc., but I think what we saw here covers a lot of what we do in a daily basis.

If this helped you, it's your turn to help me by sharing this repo with your dev network. You can also send me a message on [LinkedIn](https://www.linkedin.com/in/cicerocamargo/) or [Twitter](https://twitter.com/cicerocamargo), I'd love to hear your feedback.

If you have suggestions, corrections, etc., feel free to open a Pull Request.

See you next time!