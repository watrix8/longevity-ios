import Foundation
import SwiftUI
import Testing

@testable import Longevity

@Suite("Sygnatury i data urodzenia w opcjach")
@MainActor
struct SettingsModelTests {
    /// Znacznik zastąpił przełącznik "Podaj datę urodzenia". Bez niego profil
    /// bez daty dostałby zapisany placeholder przy edycji innego pola.
    @Test("Data urodzenia startuje jako nieustawiona")
    func birthDateStartsUnset() {
        let model = SettingsViewModel()

        #expect(model.birthDateIsSet == false)
        #expect(model.birthDate == SettingsViewModel.fallbackBirthDate)
    }

    @Test("Ustawienie daty z UI oznacza ją jako podaną")
    func setBirthDateMarksItSet() {
        let model = SettingsViewModel()
        let date = Date(timeIntervalSince1970: 520_000_000)

        model.setBirthDate(date)

        #expect(model.birthDateIsSet)
        #expect(model.birthDate == date)
    }

    /// Wartość startowa nie może wyglądać jak realna data urodzenia.
    @Test("Domyślna data nie jest dzisiejsza")
    func fallbackIsNotToday() {
        let calendar = Calendar.current
        #expect(!calendar.isDateInToday(SettingsViewModel.fallbackBirthDate))
    }

    @Test("Sygnatura profilu reaguje na każde pole")
    func profileSignatureTracksFields() {
        let model = SettingsViewModel()
        var seen: Set<String> = [model.profileSignature]

        model.fullName = "Tomasz"
        seen.insert(model.profileSignature)
        model.sex = "male"
        seen.insert(model.profileSignature)
        model.heightCm = "182"
        seen.insert(model.profileSignature)
        model.primaryGoal = "performance"
        seen.insert(model.profileSignature)
        model.bodyType = "athletic"
        seen.insert(model.profileSignature)
        model.setBirthDate(Date(timeIntervalSince1970: 1))
        seen.insert(model.profileSignature)

        // Każda zmiana musiała dać nową sygnaturę.
        #expect(seen.count == 7)
    }

    @Test("Sygnatura preferencji reaguje na każde pole")
    func prefsSignatureTracksFields() {
        let model = SettingsViewModel()
        var seen: Set<String> = [model.prefsSignature]

        model.nudgesEnabled.toggle()
        seen.insert(model.prefsSignature)
        model.nudgeTime = Date(timeIntervalSince1970: 42)
        seen.insert(model.prefsSignature)
        model.weeklyRecapEnabled.toggle()
        seen.insert(model.prefsSignature)
        model.weeklyRecapDow = 3
        seen.insert(model.prefsSignature)

        #expect(seen.count == 5)
    }

    /// Obie sekcje zapisują się osobno, więc sygnatury nie mogą się przenikać.
    @Test("Sygnatury nie przeciekają między sekcjami")
    func signaturesAreIndependent() {
        let model = SettingsViewModel()

        let prefsBefore = model.prefsSignature
        model.fullName = "Tomasz"
        #expect(model.prefsSignature == prefsBefore)

        // Punkt odniesienia bierzemy dopiero teraz — nazwisko już zmieniło
        // sygnaturę profilu i to jest oczekiwane.
        let profileBefore = model.profileSignature
        model.weeklyRecapDow = 5
        #expect(model.profileSignature == profileBefore)
    }

    @Test("Zmiana i powrót do wartości wyjściowej daje tę samą sygnaturę")
    func signatureIsStable() {
        let model = SettingsViewModel()
        let original = model.profileSignature

        model.fullName = "Tomasz"
        #expect(model.profileSignature != original)

        model.fullName = ""
        #expect(model.profileSignature == original)
    }
}

@Suite("Paleta")
struct PaletteTests {
    /// Color trzyma składowe jako Float, więc porównujemy z tolerancją,
    /// a nie co do bitu.
    @Test("Hex mapuje się na składowe RGB")
    func hexConversion() throws {
        let components = try #require(Color(hex: 0xC9781E).cgColor?.components)

        #expect(abs(components[0] - 201.0 / 255) < 1e-6)
        #expect(abs(components[1] - 120.0 / 255) < 1e-6)
        #expect(abs(components[2] - 30.0 / 255) < 1e-6)
    }
}
