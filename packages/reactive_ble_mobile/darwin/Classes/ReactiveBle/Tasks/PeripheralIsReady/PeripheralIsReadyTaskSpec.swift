import CoreBluetooth

struct PeripheralIsReadyTaskSpec: PeripheralTaskSpec {

    typealias Key = PeripheralID

    struct Params {

        let value: Data
    }

    enum Stage {

        case writing
    }

    typealias Result = Error?

    static let tag = "PERIPHERAL_IS_READY"

    static func isMember(_ key: Key, of group: PeripheralID) -> Bool {
        return key == group
    }
}
