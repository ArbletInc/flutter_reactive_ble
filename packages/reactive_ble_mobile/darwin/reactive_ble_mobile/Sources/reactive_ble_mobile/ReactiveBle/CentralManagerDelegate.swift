import CoreBluetooth

enum ConnectionChange {
    case connected
    case failedToConnect(Error?, failureReason: String?)
    case disconnected(Error?, failureReason: String?)

    /// Extract failure reason from CBError
    static func getFailureReason(from error: Error?) -> String? {
        guard let error = error as NSError? else { return nil }

        if error.domain == CBErrorDomain || error.domain == CBATTErrorDomain {
            switch error.code {
            case CBError.connectionTimeout.rawValue:
                return "connection_timeout"
            case CBATTError.insufficientEncryption.rawValue:
                return "insufficient_encryption"
            case CBATTError.insufficientAuthentication.rawValue:
                return "insufficient_authentication"
            default:
                // iOS 13.4+ specific error codes
                if #available(iOS 13.4, *) {
                    switch error.code {
                    case CBError.peerRemovedPairingInformation.rawValue:
                        return "peer_removed_pairing"
                    case CBError.encryptionTimedOut.rawValue:
                        return "encryption_timeout"
                    default:
                        break
                    }
                }
                return "unknown"
            }
        }

        return nil
    }
}

final class CentralManagerDelegate: NSObject, CBCentralManagerDelegate {

    typealias StateChangeHandler = (CBManagerState) -> Void
    typealias DiscoveryHandler = (CBPeripheral, AdvertisementData, RSSI) -> Void
    typealias ConnectionChangeHandler = (CBPeripheral, ConnectionChange) -> Void

    private let onStateChange: StateChangeHandler
    private let onDiscovery: DiscoveryHandler
    private let onConnectionChange: ConnectionChangeHandler

    init(
        onStateChange: @escaping StateChangeHandler,
        onDiscovery: @escaping DiscoveryHandler,
        onConnectionChange: @escaping ConnectionChangeHandler
    ) {
        self.onStateChange = onStateChange
        self.onDiscovery = onDiscovery
        self.onConnectionChange = onConnectionChange
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        onStateChange(central.state)
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        onDiscovery(peripheral, advertisementData, rssi.intValue)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        onConnectionChange(peripheral, .connected)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let failureReason = ConnectionChange.getFailureReason(from: error)
        onConnectionChange(peripheral, .failedToConnect(error, failureReason: failureReason))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let error = error as NSError? {
            NSLog("didDisconnectPeripheral: error domain=\(error.domain), code=\(error.code), description=\(error.localizedDescription)")
        } else {
            NSLog("didDisconnectPeripheral: no error (clean disconnect)")
        }
        let failureReason = ConnectionChange.getFailureReason(from: error)
        NSLog("didDisconnectPeripheral: extracted failureReason=\(failureReason ?? "nil")")
        onConnectionChange(peripheral, .disconnected(error, failureReason: failureReason))
    }
}
