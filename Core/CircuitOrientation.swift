import Foundation

/// OpenF1 reports positions in the timing system's own coordinate frame, so a circuit drawn as-is can face
/// any way. Each circuit here carries the rotation (degrees, counter-clockwise, y up) that turns it to the
/// orientation of the official track map. Keys are OpenF1 `circuit_short_name` values; the angles are the
/// ones MultiViewer publishes for the same coordinate frame (api.multiviewer.app/api/v1/circuits).
/// A circuit that is not listed is drawn unrotated.
public enum CircuitOrientation {
    private static let rotations: [String: Double] = [
        "Austin": 0,
        "Baku": 357,
        "Catalunya": 303,
        "Hungaroring": 40,
        "Interlagos": 258,
        "Jeddah": 104,
        "Las Vegas": 90,
        "Lusail": 61,
        "Melbourne": 44,
        "Mexico City": 36,
        "Miami": 2,
        "Monte Carlo": 315,
        "Montreal": 62,
        "Monza": 95,
        "Sakhir": 92,
        "Shanghai": 237,
        "Silverstone": 92,
        "Singapore": 335,
        "Spa-Francorchamps": 91,
        "Spielberg": 1,
        "Suzuka": 49,
        "Yas Marina Circuit": 280,
        "Zandvoort": 0,
    ]

    public static func rotation(forCircuit circuit: String?) -> Double {
        circuit.flatMap { rotations[$0.trimmingCharacters(in: .whitespacesAndNewlines)] } ?? 0
    }
}
