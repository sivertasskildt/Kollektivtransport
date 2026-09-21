# Active Transit 🚶‍♂️🚌

**Stop waiting. Start walking.** 

Active Transit is a modern iOS journey planner for Norway that flips the traditional public transport model on its head. Instead of standing at a bus stop waiting for 15 minutes, this app calculates whether you can walk to a stop further along the route and catch the exact same bus there. 

Transform dead waiting time into active walking time, reach your step goals, and arrive at your destination at the exact same time!

## ✨ Features

- **Active Transfers (Aktiv Overgang):** The core engine intercepts standard routing results and calculates if you can walk to a subsequent stop before the bus/tram departs.
- **Dynamic Routing:** Built on top of the Norwegian national journey planner (Entur). It injects custom GraphQL parameters (`walkReluctance`, `waitReluctance`) to trick the standard algorithm into suggesting alternative, faster routes for people who prefer walking over waiting.
- **Visualized Walking Routes:** Uses Apple's `MKDirections` to calculate and draw exact walking paths (green dashed lines) on the map, guiding you through streets and intersections to your optimal boarding stop.
- **Interactive Map:** A sleek, fully interactive `MapKit` integration with custom annotations for boarding stops, transfers, and your final destination.
- **Personalized Settings:** Configure your walking speed (Slow, Normal, Fast) and your reluctance to wait, which directly influences the mathematical margins of the active routing engine.

## 🛠 Tech Stack

- **UI Framework:** SwiftUI
- **Mapping & Location:** MapKit, CoreLocation, MKLocalSearch, MKDirections
- **Concurrency:** Swift `async/await`
- **Architecture:** MVVM-inspired, with the core routing engine completely isolated in a local Swift Package (`ActiveTransit`) for ultimate testability and modularity.
- **Data Source:** Entur OpenTripPlanner (OTP) GraphQL API

## 📦 Project Structure

The project is divided into two main parts:
1. **The iOS App (`KollektivApp`):** Handles the UI (SwiftUI), Map rendering, and User Settings (`@AppStorage` / `@EnvironmentObject`).
2. **The ActiveTransit Package:** A standalone Swift Package containing the `ActiveRouter` engine, network clients, and data models. This enforces strict separation of concerns.

## 🚀 Getting Started

1. Clone the repository.
2. Open the project in **Xcode 15+**.
3. *Note on Simulators:* If you experience crashes when panning the map in the iOS Simulator, disable **Metal API Validation** in your Xcode Scheme settings (this is a known Apple Simulator bug related to `MapPolyline`).
4. Build and run on an iOS Simulator or physical device running iOS 17+.

## 🤝 Acknowledgements
Routing data is provided by [Entur API](https://developer.entur.org/). 

---
*Built with ❤️ for health, efficiency, and writing great Swift code.*
