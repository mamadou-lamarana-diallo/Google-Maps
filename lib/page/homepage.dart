import 'dart:async';
import 'dart:developer';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_routes/google_maps_routes.dart';
import 'package:localzation/constants/constants.dart';
import 'package:localzation/service/permission_provider.dart';
import 'package:maps_toolkit/maps_toolkit.dart' as mtk;
import 'package:permission_handler/permission_handler.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final Completer<GoogleMapController> _controller = Completer<GoogleMapController>();
  String _darkMapStyle = "";
  StreamSubscription<Position>? _positionStream;
  CameraPosition? _cameraPos;
  List<Marker> markerList = [];
  Marker? _destinationMarker;
  Position? _currentPosition;
  List<Polyline> myRouteList = [];
  MapsRoutes route = MapsRoutes();
  BitmapDescriptor markerIcon = BitmapDescriptor.defaultMarker;
  Marker? myLocationMarker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _currentPosition = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _cameraPos = CameraPosition(
          target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          zoom: 16,
        );
      });
      setCustomIconForUserLocation();
      _loadMapStyles().then((_) {
        if (mounted) setState(() {});
      });
      checkPermissionAndListenLocation();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_positionStream != null) _positionStream!.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.grey[850],
        onPressed: () {
          getNewRouteFromAPI();
        },
        label: Text(
          "Get Route",
          style: TextStyle(color: Colors.grey[300]),
        ),
      ),
      appBar: AppBar(
        backgroundColor: Colors.grey[850],
        centerTitle: true,
        title: Text("RMD Navigation Service",
            style: TextStyle(color: Colors.grey[300])),
      ),
      body: !PermissionProvider.isServiceOn ||
          PermissionProvider.locationPermission != PermissionStatus.granted ||
          _darkMapStyle.isEmpty
          ? Container(
          color: Colors.grey[700],
          child: const Center(child: CircularProgressIndicator()))
          : GoogleMap(
        mapType: MapType.normal,
        myLocationEnabled: true,
        polylines: Set<Polyline>.from(myRouteList),
        initialCameraPosition: _cameraPos ?? const CameraPosition(
            target: LatLng(48.14918762944394, 11.580469375826612), zoom: 16),
        markers: Set<Marker>.from(markerList),
        onMapCreated: (GoogleMapController controller) {
          if (!_controller.isCompleted) {
            _controller.complete(controller);
          }
        },
        onTap: (LatLng position) {
          setNewDestination(position);
        },
      ),
    );
  }

  void setCustomIconForUserLocation() {
    Future<Uint8List> getBytesFromAsset(String path, int width) async {
      ByteData data = await rootBundle.load(path);
      Codec codec = await instantiateImageCodec(data.buffer.asUint8List(),
          targetWidth: width);
      FrameInfo fi = await codec.getNextFrame();
      return (await fi.image.toByteData(format: ImageByteFormat.png))!
          .buffer
          .asUint8List();
    }

    getBytesFromAsset('assets/user_location.png', 64).then((onValue) {
      markerIcon = BitmapDescriptor.fromBytes(onValue);
    });
  }

  void navigationProcess() {
    List<mtk.LatLng> myLatLngList = [];
    for (var data in route.routes.first.points) {
      myLatLngList.add(mtk.LatLng(data.latitude, data.longitude));
    }
    mtk.LatLng myPosition =
    mtk.LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    // we check if our location is on route or not
    int x = mtk.PolygonUtil.locationIndexOnPath(myPosition, myLatLngList, true,
        tolerance: 12);
    if (x == -1) {
      getNewRouteFromAPI();
    } else {
      myLatLngList[x] = myPosition;
      myLatLngList.removeRange(0, x);
      myRouteList.first.points.clear();
      myRouteList.first.points
          .addAll(myLatLngList.map((e) => LatLng(e.latitude, e.longitude)));
    }
    if (mounted) setState(() {});
  }

  void getNewRouteFromAPI() async {
    if (_currentPosition == null || _destinationMarker == null) return;

    if (route.routes.isNotEmpty) route.routes.clear();
    if (myRouteList.isNotEmpty) myRouteList.clear();
    log("GETTING NEW ROUTE !!");
    await route.drawRoute([
      LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
      LatLng(_destinationMarker!.position.latitude,
          _destinationMarker!.position.longitude)
    ], 'route', const Color.fromARGB(255, 33, 155, 255), Constants.googleApiKey,
        travelMode: TravelModes.driving);
    myRouteList.add(route.routes.first);
    if (mounted) setState(() {});
  }

  void setNewDestination(LatLng position) {
    setState(() {
      _destinationMarker = Marker(
        markerId: MarkerId("destination"),
        position: position,
      );
      markerList.add(_destinationMarker!);
    });
    getNewRouteFromAPI();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (PermissionProvider.permissionDialogRoute != null &&
          PermissionProvider.permissionDialogRoute!.isActive) {
        Navigator.of(Constants.globalNavigatorKey.currentContext!)
            .removeRoute(PermissionProvider.permissionDialogRoute!);
      }
      Future.delayed(const Duration(milliseconds: 240), () async {
        checkPermissionAndListenLocation();
      });
    }
  }

  Future<void> _loadMapStyles() async {
    _darkMapStyle = await rootBundle.loadString(Constants.darkMapStyleJson);
  }

  void checkPermissionAndListenLocation() {
    PermissionProvider.handleLocationPermission().then((_) {
      if (_positionStream == null &&
          PermissionProvider.isServiceOn &&
          PermissionProvider.locationPermission == PermissionStatus.granted) {
        startListeningLocation();
      }
      if (mounted) setState(() {});
    });
  }

  void startListeningLocation() {
    _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high))
        .listen((Position? position) {
      if (position != null) {
        log('${position.latitude.toString()}, ${position.longitude.toString()}');
        showMyLocationOnMap(position);
        if (myRouteList.isNotEmpty) {
          navigationProcess();
        }
      }
    });
  }

  void showMyLocationOnMap(Position position) {
    _currentPosition = position;
    markerList.removeWhere((e) => e.markerId == const MarkerId("myLocation"));
    myLocationMarker = Marker(
        markerId: const MarkerId("myLocation"),
        position: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        icon: markerIcon,
        rotation: _currentPosition!.heading);
    if (markerIcon != BitmapDescriptor.defaultMarker) {
      markerList.add(myLocationMarker!);
    }
    if (mounted) setState(() {});
  }
}
