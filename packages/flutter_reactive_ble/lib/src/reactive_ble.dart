import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/src/connected_device_operation.dart';
import 'package:flutter_reactive_ble/src/debug_logger.dart';
import 'package:flutter_reactive_ble/src/device_connector.dart';
import 'package:flutter_reactive_ble/src/device_scanner.dart';
import 'package:flutter_reactive_ble/src/discovered_devices_registry.dart';
import 'package:flutter_reactive_ble/src/rx_ext/repeater.dart';
import 'package:meta/meta.dart';
import 'package:reactive_ble_mobile/reactive_ble_mobile.dart';
import 'package:reactive_ble_platform_interface/reactive_ble_platform_interface.dart';

/// [FlutterReactiveBle] is the facade of the library. Its interface allows to
/// perform all the supported BLE operations.
class FlutterReactiveBle {
  static final FlutterReactiveBle _sharedInstance = FlutterReactiveBle._();

  factory FlutterReactiveBle() => _sharedInstance;

  ///Create a new instance where injected dependencies are used.
  @visibleForTesting
  FlutterReactiveBle.witDependencies({
    required DeviceScanner deviceScanner,
    required DeviceConnector deviceConnector,
    required ConnectedDeviceOperation connectedDeviceOperation,
    required Logger debugLogger,
    required Future<void> initialization,
    required ReactiveBlePlatform reactiveBlePlatform,
  }) {
    _deviceScanner = deviceScanner;
    _deviceConnector = deviceConnector;
    _connectedDeviceOperator = connectedDeviceOperation;
    _debugLogger = debugLogger;
    _initialization = initialization;
    _blePlatform = reactiveBlePlatform;
    _trackStatus();
  }

  FlutterReactiveBle._() {
    _trackStatus();
  }

  /// Registry that keeps track of all BLE devices found during a BLE scan.
  final scanRegistry = DiscoveredDevicesRegistryImpl.standard();

  /// A stream providing the host device BLE subsystem status updates.
  ///
  /// Also see [status].
  Stream<BleStatus> statusStream({required bool showIosPowerAlert}) => Repeater(onListenEmitFrom: () async* {
        await initialize(showIosPowerAlert: showIosPowerAlert);
        yield _status;
        yield* _statusStream;
      }).stream;

  /// Returns the current status of the BLE subsystem of the host device.
  ///
  /// Also see [statusStream].
  BleStatus get status => _status;

  /// A stream providing connection updates for all the connected BLE devices.
  Stream<ConnectionStateUpdate> get connectedDeviceStream => Repeater.broadcast(onListenEmitFrom: () async* {
        await initialize();
        yield* _deviceConnector.deviceConnectionStateUpdateStream;
      }).stream;

  /// A stream providing value updates for all the connected BLE devices.
  ///
  /// The updates include read responses as well as notifications.
  Stream<CharacteristicValue> get characteristicValueStream async* {
    await initialize();
    yield* _connectedDeviceOperator.characteristicValueStream;
  }

  late ReactiveBlePlatform _blePlatform;

  BleStatus _status = BleStatus.unknown;

  Stream<BleStatus> get _statusStream => _blePlatform.bleStatusStream;

  Future<void> _trackStatus() async {
    await initialize(showIosPowerAlert: false); // 最初はiOSのためpopupオフ(Androidは関係ない).
    _statusStream.listen((status) => _status = status);
  }

  Future<void>? _initialization;

  late DeviceConnector _deviceConnector;
  late ConnectedDeviceOperation _connectedDeviceOperator;
  late DeviceScanner _deviceScanner;
  late Logger _debugLogger;

  bool? isShowIosPowerAlert; // iOSではBLE接続状態取得時(アプリで説明表示前)はBLEをONするポップアップを出したくないため、フラグで管理する.

  /// Initializes this [FlutterReactiveBle] instance and its platform-specific
  /// counterparts.
  ///
  /// The initialization is performed automatically the first time any BLE
  /// operation is triggered.
  Future<void> initialize({bool showIosPowerAlert = true}) async {
    if (_initialization == null) {
      isShowIosPowerAlert = showIosPowerAlert;
      debugPrint('initialize:_initialization:showIosPowerAlert:$showIosPowerAlert');
      _debugLogger = DebugLogger(
        'REACTIVE_BLE',
        print,
      );

      if (Platform.isAndroid || Platform.isIOS) {
        ReactiveBlePlatform.instance = const ReactiveBleMobilePlatformFactory().create(
          logger: _debugLogger,
        );
      }

      _blePlatform = ReactiveBlePlatform.instance;

      _initialization ??= _blePlatform.initialize(showIosPowerAlert: showIosPowerAlert);

      _connectedDeviceOperator = ConnectedDeviceOperationImpl(
        blePlatform: _blePlatform,
      );
      _deviceScanner = DeviceScannerImpl(
        blePlatform: _blePlatform,
        platformIsAndroid: () => Platform.isAndroid,
        delayAfterScanCompletion: Future<void>.delayed(
          const Duration(milliseconds: 300),
        ),
        addToScanRegistry: scanRegistry.add,
      );

      _deviceConnector = DeviceConnectorImpl(
        blePlatform: _blePlatform,
        deviceIsDiscoveredRecently: scanRegistry.deviceIsDiscoveredRecently,
        deviceScanner: _deviceScanner,
        delayAfterScanFailure: const Duration(seconds: 10),
      );

      await _initialization;
    }
  }

  /// Deinitializes this [FlutterReactiveBle] instance and its platform-specific
  /// counterparts.
  ///
  /// The deinitialization is automatically performed on Flutter Hot Restart.
  Future<void> deinitialize() async {
    if (_initialization != null) {
      _initialization = null;
      await _disconnectionUpdates?.cancel();
      _disconnectionUpdates = null;
      await _blePlatform.deinitialize();
    }
  }

  /// Reads the value of the specified characteristic.
  ///
  /// The returned future completes with an error in case of a failure during reading.
  ///
  /// Be aware that a read request could be satisfied by a notification delivered
  /// for the same characteristic via [characteristicValueStream] before the actual
  /// read response arrives (due to the design of iOS BLE API).
  ///
  /// This method assumes there is a single characteristic with the ids specified in [characteristic]. If there are
  /// multiple characteristics with the same id on a device, use [resolve] to find them all. Or use
  /// [getDiscoveredServices] to select the [Service]s and [Characteristic]s you're interested in.
  Future<List<int>> readCharacteristic(QualifiedCharacteristic characteristic) async {
    await initialize();
    return (await resolveSingle(characteristic)).read();
  }

  /// Writes a value to the specified characteristic awaiting for an acknowledgement.
  ///
  /// The returned future completes with an error in case of a failure during writing.
  ///
  /// This method assumes there is a single characteristic with the ids specified in [characteristic]. If there are
  /// multiple characteristics with the same id on a device, use [resolve] to find them all. Or use
  /// [getDiscoveredServices] to select the [Service]s and [Characteristic]s you're interested in.
  Future<void> writeCharacteristicWithResponse(
    QualifiedCharacteristic characteristic, {
    required List<int> value,
  }) async {
    await initialize();
    await (await resolveSingle(characteristic)).write(value, withResponse: true);
  }

  /// Writes a value to the specified characteristic without waiting for an acknowledgement.
  ///
  /// Use this method in case the  client does not need an acknowledgement
  /// that the write was successfully performed. For subsequent write operations it is
  /// recommended to execute a [writeCharacteristicWithResponse] each n times to make sure
  /// the BLE device is still responsive.
  ///
  /// The returned future completes with an error in case of a failure during writing.
  ///
  /// This method assumes there is a single characteristic with the ids specified in [characteristic]. If there are
  /// multiple characteristics with the same id on a device, use [resolve] to find them all. Or use
  /// [getDiscoveredServices] to select the [Service]s and [Characteristic]s you're interested in.
  Future<void> writeCharacteristicWithoutResponse(
    QualifiedCharacteristic characteristic, {
    required List<int> value,
  }) async {
    await initialize();
    await (await resolveSingle(characteristic)).write(value, withResponse: false);
  }

  /// Request a specific MTU for a connected device.
  ///
  /// Returns the actual MTU negotiated.
  ///
  /// For reference:
  ///
  /// * BLE 4.0–4.1 max ATT MTU is 23 bytes
  /// * BLE 4.2–5.1 max ATT MTU is 247 bytes
  Future<int> requestMtu({required String deviceId, required int mtu}) async {
    await initialize();
    return _connectedDeviceOperator.requestMtu(deviceId, mtu);
  }

  /// Requests for a connection parameter update on the connected device.
  ///
  /// Always completes with an error on iOS, as there is no way (and no need) to perform this operation on iOS.
  Future<void> requestConnectionPriority({required String deviceId, required ConnectionPriority priority}) async {
    await initialize();

    return _connectedDeviceOperator.requestConnectionPriority(deviceId, priority);
  }

  /// Scan for BLE peripherals advertising the services specified in [withServices]
  /// or for all BLE peripherals, if no services is specified. It is recommended to always specify some services.
  ///
  /// There are two Android specific parameters that are ignored on iOS:
  ///
  /// - [scanMode] allows to choose between different levels of power efficient and/or low latency scan modes.
  /// - [requireLocationServicesEnabled] specifies whether to check if location services are enabled before scanning.
  ///   When set to true and location services are disabled, an exception is thrown. Default is true.
  ///   Setting the value to false can result in not finding BLE peripherals on some Android devices.
  Stream<DiscoveredDevice> scanForDevices({
    required List<Uuid> withServices,
    ScanMode scanMode = ScanMode.balanced,
    bool requireLocationServicesEnabled = true,
  }) async* {
    debugPrint('scanForDevices!!!');
    await initialize();

    yield* _deviceScanner.scanForDevices(
      withServices: withServices,
      scanMode: scanMode,
      requireLocationServicesEnabled: requireLocationServicesEnabled,
    );
  }

  /// Establishes a connection to a BLE device.
  ///
  /// Disconnecting the device is achieved by cancelling the stream subscription.
  ///
  /// [id] is the unique device id of the BLE device: in iOS this is a uuid and on Android this is
  /// a Mac-Address.
  /// Use [servicesWithCharacteristicsToDiscover] to scan only for the specific services mentioned in this map,
  /// this can improve the connection speed on iOS since no full service discovery will be executed. On Android
  /// this variable is ignored since partial discovery is not possible.
  /// If [connectionTimeout] parameter is supplied and a connection is not established before [connectionTimeout] expires,
  /// the pending connection attempt will be cancelled and a [TimeoutException] error will be emitted into the returned stream.
  /// On Android when no timeout is specified the `autoConnect` flag is set in the
  /// [connectGatt()](https://developer.android.com/reference/android/bluetooth/BluetoothDevice#connectGatt(android.content.Context,%20boolean,%20android.bluetooth.BluetoothGattCallback))
  /// call, otherwise it is cleared.
  Stream<ConnectionStateUpdate> connectToDevice({
    required String id,
    Map<Uuid, List<Uuid>>? servicesWithCharacteristicsToDiscover,
    Duration? connectionTimeout,
  }) =>
      initialize().asStream().asyncExpand(
            (_) => _deviceConnector.connect(
              id: id,
              servicesWithCharacteristicsToDiscover: servicesWithCharacteristicsToDiscover,
              connectionTimeout: connectionTimeout,
            ),
          );

  /// Scans for a specific device and connects to it in case a device containing the specified [id]
  /// is found and that is advertising the services specified in [withServices].
  ///
  /// Disconnecting the device is achieved by cancelling the stream subscription.
  ///
  /// The [prescanDuration] is the amount of time BLE discovery should run in order to find the device.
  /// Use [servicesWithCharacteristicsToDiscover] to scan only for the specific services mentioned in this map,
  /// this can improve the connection speed on iOS since no full service discovery will be executed. On Android
  /// this variable is ignored since partial discovery is not possible.
  /// If [connectionTimeout] parameter is supplied and a connection is not established before [connectionTimeout] expires,
  /// the pending connection attempt will be cancelled and a [TimeoutException] error will be emitted into the returned stream.
  /// On Android when no timeout is specified the `autoConnect` flag is set in the
  /// [connectGatt()](https://developer.android.com/reference/android/bluetooth/BluetoothDevice#connectGatt(android.content.Context,%20boolean,%20android.bluetooth.BluetoothGattCallback))
  /// call, otherwise it is cleared.
  Stream<ConnectionStateUpdate> connectToAdvertisingDevice({
    required String id,
    required List<Uuid> withServices,
    required Duration prescanDuration,
    Map<Uuid, List<Uuid>>? servicesWithCharacteristicsToDiscover,
    Duration? connectionTimeout,
  }) =>
      initialize().asStream().asyncExpand(
            (_) => _deviceConnector.connectToAdvertisingDevice(
              id: id,
              withServices: withServices,
              prescanDuration: prescanDuration,
              servicesWithCharacteristicsToDiscover: servicesWithCharacteristicsToDiscover,
              connectionTimeout: connectionTimeout,
            ),
          );

  /// Performs service discovery on the peripheral and returns the discovered services.
  ///
  /// When discovery fails this method throws an [Exception].
  @Deprecated("Use `discoverAllServices` and `getDiscoverServices`")
  Future<List<DiscoveredService>> discoverServices(String deviceId) =>
      _connectedDeviceOperator.discoverServices(deviceId);

  /// Performs service discovery on the peripheral.
  ///
  /// When discovery fails this method throws an [Exception].
  ///
  /// Use [getDiscoveredServices] to get the discovered services
  Future<void> discoverAllServices(String deviceId) => _connectedDeviceOperator.discoverServices(deviceId);

  /// Services can be discovered by:
  /// - specify `servicesWithCharacteristicsToDiscover` in [connectToDevice] or [connectToAdvertisingDevice]. Or,
  /// - by calling [discoverAllServices]
  ///
  /// Discovered services and charactersitcs remain valid for as long as the device stays connected. After reconnecting
  /// to a device, [getDiscoveredServices] must be called again to get updated services and characteristics.
  ///
  /// Note: On Android, this method performs service discovery if one was done yet after connecting the device.
  Future<List<Service>> getDiscoveredServices(String deviceId) async {
    _disconnectionUpdates ??= connectedDeviceStream
        .where((update) => update.connectionState == DeviceConnectionState.disconnected)
        .listen((update) {
      _services[update.deviceId]?.forEach((service) => service._markInvalid());
      _services[update.deviceId]?.clear();
    });

    final discoveredServices = await _connectedDeviceOperator.getDiscoverServices(deviceId);

    final services = _services[deviceId] ?? [];

    for (final discoveredService in discoveredServices) {
      final service = services.firstWhere(
        (service) => _isMatchingService(service, discoveredService),
        orElse: () {
          final newService = Service._(
            id: discoveredService.serviceId,
            instanceId: discoveredService.serviceInstanceId,
            deviceId: deviceId,
          );
          services.add(newService);
          return newService;
        },
      );

      for (final discoveredCharacteristic in discoveredService.characteristics) {
        if (!service._characteristics.any((char) => _isMatchingCharacteristic(char, discoveredCharacteristic))) {
          service._characteristics.add(Characteristic._(
            id: discoveredCharacteristic.characteristicId,
            instanceId: discoveredCharacteristic.characteristicInstanceId,
            service: service,
            lib: this,
            isReadable: discoveredCharacteristic.isReadable,
            isWritableWithoutResponse: discoveredCharacteristic.isWritableWithoutResponse,
            isWritableWithResponse: discoveredCharacteristic.isWritableWithResponse,
            isNotifiable: discoveredCharacteristic.isNotifiable,
            isIndicatable: discoveredCharacteristic.isIndicatable,
          ));
        }
      }
      service._characteristics.removeWhere((char) => !discoveredService.characteristics.any(
            (discoveredCharacteristic) => _isMatchingCharacteristic(char, discoveredCharacteristic),
          ));
    }
    services.removeWhere(
      (service) => !discoveredServices.any((discoveredService) => _isMatchingService(service, discoveredService)),
    );

    return UnmodifiableListView(services);
  }

  StreamSubscription<ConnectionStateUpdate>? _disconnectionUpdates;

  bool _isMatchingService(Service service, DiscoveredService discoveredService) =>
      service.id == discoveredService.serviceId && service._instanceId == discoveredService.serviceInstanceId;

  bool _isMatchingCharacteristic(Characteristic char, DiscoveredCharacteristic discoveredCharacteristic) =>
      char.id == discoveredCharacteristic.characteristicId &&
      char._instanceId == discoveredCharacteristic.characteristicInstanceId;

  final _services = <String, List<Service>>{};

  /// Clears GATT attribute cache on Android using undocumented API. Completes with an error in case of a failure.
  ///
  /// Always completes with an error on iOS, as there is no way (and no need) to perform this operation on iOS.
  ///
  /// The connection may need to be reestablished after successful GATT attribute cache clearing.
  Future<void> clearGattCache(String deviceId) =>
      _blePlatform.clearGattCache(deviceId).then((info) => info.dematerialize());

  /// Reads the RSSI of the of the peripheral with the given device ID.
  /// The peripheral must be connected, otherwise a [PlatformException] will be
  /// thrown
  Future<int> readRssi(String deviceId) async => _blePlatform.readRssi(deviceId);

  /// Subscribes to updates from the characteristic specified.
  ///
  /// This stream terminates automatically when the device is disconnected.
  ///
  /// This method assumes there is a single characteristic with the ids specified in [characteristic]. If there are
  /// multiple characteristics with the same id on a device, use [resolve] to find them all. Or use
  /// [getDiscoveredServices] to select the [Service]s and [Characteristic]s you're interested in.
  Stream<List<int>> subscribeToCharacteristic(QualifiedCharacteristic characteristic) async* {
    yield* (await resolveSingle(characteristic)).subscribe();
  }

  Future<Iterable<Characteristic>> resolve(QualifiedCharacteristic characteristic) async {
    final services = await getDiscoveredServices(characteristic.deviceId);
    return services
        .withId(characteristic.serviceId)
        .expand((service) => service.characteristics.withId(characteristic.characteristicId));
  }

  Future<Characteristic> resolveSingle(QualifiedCharacteristic characteristic) async {
    final chars = await resolve(characteristic);
    if (chars.isEmpty) throw Exception("Characteristic not found or discovered: $characteristic");
    if (chars.length > 1) throw Exception("Multiple matching characteristics found: $characteristic");
    return chars.single;
  }

  /// Sets the verbosity of debug output.
  ///
  /// Use [LogLevel.verbose] for full debug output. Make sure to  run this only for debugging purposes.
  /// Use [LogLevel.none] to disable logging. This is also the default.
  set logLevel(LogLevel logLevel) => _debugLogger.logLevel = logLevel;

  LogLevel get logLevel => _debugLogger.logLevel;
}

/// An instance of this object should not be used after its device has lost its connection.
class Service {
  Service._({
    required this.id,
    required String instanceId,
    required this.deviceId,
  }) : _instanceId = instanceId;

  final Uuid id;

  // Not exposed as it may be different each time a device is connected to, so it should not be used to identify
  // services. Instead, services have to be discovered after connecting and looked up via
  // [FlutterReactiveBle.getDiscoverServices]
  final String _instanceId;

  final String deviceId;

  /// Discovered characteristics
  List<Characteristic> get characteristics => UnmodifiableListView(_characteristics);

  final List<Characteristic> _characteristics = [];

  // A Service becomes invalid when its device gets disconnected. After reconnecting to the device, services have to be
  // rediscovered
  void _markInvalid() {
    for (final characteristic in _characteristics) {
      characteristic._markInvalid();
    }
  }

  @override
  String toString() => "Service($id)";
}

/// An instance of this object should not be used after its device has lost its connection.
class Characteristic {
  Characteristic._({
    required this.id,
    required String instanceId,
    required this.service,
    required FlutterReactiveBle lib,
    required this.isReadable,
    required this.isWritableWithoutResponse,
    required this.isWritableWithResponse,
    required this.isNotifiable,
    required this.isIndicatable,
  })  : _instanceId = instanceId,
        _lib = lib;

  final Uuid id;

  /// The service containing this characteristic
  final Service service;

  // Not exposed as it may be different each time a device is connected to, so it should not be used to identify
  // characteristics. Instead, characteristics have to be discovered after connecting and looked up via
  // [FlutterReactiveBle.getDiscoverServices]
  final String _instanceId;

  final bool isReadable;
  final bool isWritableWithoutResponse;
  final bool isWritableWithResponse;
  final bool isNotifiable;
  final bool isIndicatable;

  /// Reads the value of the specified characteristic.
  ///
  /// The returned future completes with an error in case of a failure during reading.
  ///
  /// Be aware that a read request could be satisfied by a notification delivered
  /// for the same characteristic via [FlutterReactiveBle.characteristicValueStream] before the actual
  /// read response arrives (due to the design of iOS BLE API).
  Future<List<int>> read() {
    _assertValidity();
    return _lib._connectedDeviceOperator.readCharacteristic(_ids);
  }

  /// Writes a value to the specified characteristic.
  ///
  /// When [withResponse] is false, writing is done without waiting for an acknowledgement.
  /// Use this in case client does not need an acknowledgement
  /// that the write was successfully performed. For consequitive write operations it is
  /// recommended to execute a write with [withResponse] true each n times to make sure
  /// the BLE device is still responsive.
  ///
  /// The returned future completes with an error in case of a failure during writing.
  Future<void> write(List<int> value, {bool withResponse = true}) async {
    _assertValidity();

    if (withResponse) {
      await _lib._connectedDeviceOperator.writeCharacteristicWithResponse(_ids, value: value);
    } else {
      await _lib._connectedDeviceOperator.writeCharacteristicWithoutResponse(_ids, value: value);
    }
  }

  /// Subscribes to updates from the characteristic specified.
  ///
  /// This stream terminates automatically when the device is disconnected.
  Stream<List<int>> subscribe() {
    _assertValidity();

    final isDisconnected = _lib.connectedDeviceStream
        .where((update) =>
            update.deviceId == service.deviceId &&
            (update.connectionState == DeviceConnectionState.disconnecting ||
                update.connectionState == DeviceConnectionState.disconnected))
        .cast<void>()
        .firstWhere((_) => true, orElse: () {});

    return _lib.initialize().asStream().asyncExpand(
          (_) => _lib._connectedDeviceOperator.subscribeToCharacteristic(
            CharacteristicInstance(
              characteristicId: id,
              characteristicInstanceId: _instanceId,
              serviceId: service.id,
              serviceInstanceId: service._instanceId,
              deviceId: service.deviceId,
            ),
            isDisconnected,
          ),
        );
  }

  // A Characteristic becomes invalid when its device gets disconnected. After reconnecting to the device,
  // services and characteristics have to be rediscovered
  bool _valid = true;

  void _markInvalid() {
    _valid = false;
  }

  void _assertValidity() {
    if (!_valid) {
      throw Exception(
        "Characteristic no longer valid. Characteristics lose their validity after a device gets disconnected. "
        "Rediscover services and characteristics after reconnecting to the device.",
      );
    }
  }

  final FlutterReactiveBle _lib;

  CharacteristicInstance get _ids => CharacteristicInstance(
        characteristicId: id,
        characteristicInstanceId: _instanceId,
        serviceId: service.id,
        serviceInstanceId: service._instanceId,
        deviceId: service.deviceId,
      );

  @override
  String toString() => "Characteristic($id; $_instanceId; ${service._instanceId})";
}

extension ServiceWithId on Iterable<Service> {
  Iterable<Service> withId(Uuid id) => where((s) => s.id.expanded == id.expanded);
}

extension CharacteristicWithId on Iterable<Characteristic> {
  Iterable<Characteristic> withId(Uuid id) => where((c) => c.id.expanded == id.expanded);
}
