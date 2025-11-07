// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'connection_state_update.dart';

// **************************************************************************
// FunctionalDataGenerator
// **************************************************************************

abstract class $ConnectionStateUpdate {
  const $ConnectionStateUpdate();

  String get deviceId;
  DeviceConnectionState get connectionState;
  GenericFailure<ConnectionError>? get failure;
  String? get failureReason;

  ConnectionStateUpdate copyWith({
    String? deviceId,
    DeviceConnectionState? connectionState,
    GenericFailure<ConnectionError>? failure,
    String? failureReason,
  }) =>
      ConnectionStateUpdate(
        deviceId: deviceId ?? this.deviceId,
        connectionState: connectionState ?? this.connectionState,
        failure: failure ?? this.failure,
        failureReason: failureReason ?? this.failureReason,
      );

  ConnectionStateUpdate copyUsing(
      void Function(ConnectionStateUpdate$Change change) mutator) {
    final change = ConnectionStateUpdate$Change._(
      this.deviceId,
      this.connectionState,
      this.failure,
      this.failureReason,
    );
    mutator(change);
    return ConnectionStateUpdate(
      deviceId: change.deviceId,
      connectionState: change.connectionState,
      failure: change.failure,
      failureReason: change.failureReason,
    );
  }

  @override
  String toString() =>
      "ConnectionStateUpdate(deviceId: $deviceId, connectionState: $connectionState, failure: $failure, failureReason: $failureReason)";

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes
  bool operator ==(Object other) =>
      other is ConnectionStateUpdate &&
      other.runtimeType == runtimeType &&
      deviceId == other.deviceId &&
      connectionState == other.connectionState &&
      failure == other.failure &&
      failureReason == other.failureReason;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes
  int get hashCode {
    var result = 17;
    result = 37 * result + deviceId.hashCode;
    result = 37 * result + connectionState.hashCode;
    result = 37 * result + failure.hashCode;
    result = 37 * result + failureReason.hashCode;
    return result;
  }
}

class ConnectionStateUpdate$Change {
  ConnectionStateUpdate$Change._(
    this.deviceId,
    this.connectionState,
    this.failure,
    this.failureReason,
  );

  String deviceId;
  DeviceConnectionState connectionState;
  GenericFailure<ConnectionError>? failure;
  String? failureReason;
}

// ignore: avoid_classes_with_only_static_members
class ConnectionStateUpdate$ {
  static final deviceId = Lens<ConnectionStateUpdate, String>(
    (deviceIdContainer) => deviceIdContainer.deviceId,
    (deviceIdContainer, deviceId) =>
        deviceIdContainer.copyWith(deviceId: deviceId),
  );

  static final connectionState =
      Lens<ConnectionStateUpdate, DeviceConnectionState>(
    (connectionStateContainer) => connectionStateContainer.connectionState,
    (connectionStateContainer, connectionState) =>
        connectionStateContainer.copyWith(connectionState: connectionState),
  );

  static final failure =
      Lens<ConnectionStateUpdate, GenericFailure<ConnectionError>?>(
    (failureContainer) => failureContainer.failure,
    (failureContainer, failure) => failureContainer.copyWith(failure: failure),
  );

  static final failureReason = Lens<ConnectionStateUpdate, String?>(
    (failureReasonContainer) => failureReasonContainer.failureReason,
    (failureReasonContainer, failureReason) =>
        failureReasonContainer.copyWith(failureReason: failureReason),
  );
}
