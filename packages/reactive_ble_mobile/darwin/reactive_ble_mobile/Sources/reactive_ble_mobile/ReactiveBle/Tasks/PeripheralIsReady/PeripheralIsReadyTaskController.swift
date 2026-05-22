import CoreBluetooth

struct PeripheralIsReadyTaskController: PeripheralTaskController {

    typealias TaskSpec = PeripheralIsReadyTaskSpec

    private let task: SubjectTask

    init(_ task: SubjectTask) {
        self.task = task
    }

    func start(peripheral: CBPeripheral, characteristic: CharacteristicInstance) -> SubjectTask {
        guard
            peripheral.state == .connected,
            let service = peripheral.services?.filter({ $0.uuid == characteristic.serviceID })[Int(characteristic.serviceInstanceID) ?? 0],
            let char = service.characteristics?.filter({ $0.uuid == characteristic.id })[Int(characteristic.instanceID) ?? 0],
            char.properties.contains(.writeWithoutResponse)
        else {
            return task.with(state: task.state.finished(PluginError.internalInconcictency(details: nil)))
        }

        peripheral.writeValue(task.params.value, for: char, type: .withoutResponse)

        return task.with(state: task.state.processing(.writing))
    }

    func cancel(error: Error) -> SubjectTask {
        return task.with(state: task.state.finished(error))
    }

    func handleWrite(error: Error?) -> SubjectTask {
        return task.with(state: task.state.finished(error))
    }
}
