import CoreBluetooth

struct ConnectTaskController: PeripheralTaskController {

    typealias TaskSpec = ConnectTaskSpec

    private let task: SubjectTask

    init(_ task: SubjectTask) {
        self.task = task
    }

    func connect(centralManager: CBCentralManager, peripheral: CBPeripheral) -> SubjectTask {
        guard case .pending = task.state
        else {
            assert(false)
            return task
        }

        centralManager.connect(peripheral)

        return task.with(state: task.state.processing(.connecting))
    }

    func handleConnectionChange(_ connectionChange: ConnectionChange) -> SubjectTask {
        guard case .processing(since: _, .connecting) = task.state
        else {
            assert(false)
            return task
        }

        return task.with(state: task.state.finished(connectionChange))
    }

    func cancel(centralManager: CBCentralManager, peripheral: CBPeripheral, error: Error?) -> SubjectTask {
        let failureReason = ConnectionChange.getFailureReason(from: error)
        switch task.state {
        case .pending:
            return task.with(state: task.state.finished(.failedToConnect(error, failureReason: failureReason)))
        case .processing(since: _, .connecting):
            centralManager.cancelPeripheralConnection(peripheral)
            return task.with(state: task.state.finished(.failedToConnect(error, failureReason: failureReason)))
        case .finished:
            assert(false)
            return task
        }
    }
}
