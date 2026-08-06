# Longevity iOS

Passive health tracker with Apple Watch companion. Backend: Next.js + Supabase (longevity-chi.vercel.app).

## Structure

```
Longevity/              — iOS app (SwiftUI)
  HealthKit/            — HealthKit integration
  Supabase/             — Supabase client config
LongevityWatch/         — watchOS app
LongevityWatchExtension/— watch extension (complications)
project.yml             — XcodeGen project definition
```

## Setup

```bash
# Generate Xcode project
xcodegen generate

# Build
xcodebuild -scheme Longevity -destination "platform=iOS Simulator,name=iPhone 17" build

# Or for device (no simulator needed)
xcodebuild -scheme Longevity -destination "generic/platform=iOS" build
```

## Requirements

- Xcode 26+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- iOS 26.0 deployment target
