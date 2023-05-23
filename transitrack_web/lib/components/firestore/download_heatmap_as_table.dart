import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:universal_html/html.dart' as html;

import '../../address_finder.dart';
import '../../config/route_coordinates.dart';
import '../../models/heatmap_model.dart';


Future<void> downloadHeatMapCollectionAsCSV(int routeId, Timestamp start, Timestamp end) async {
  Query<Map<String, dynamic>> heatmapRef = FirebaseFirestore.instance
      .collection('heatmap_ride')
      .where('route_id', isEqualTo: routeId)
      .where('timestamp', isGreaterThanOrEqualTo: start)
      .where('timestamp', isLessThanOrEqualTo: end);

  var querySnapshot = await heatmapRef.get();
  var heatMapDataRideList = querySnapshot.docs.map((doc) => HeatMapData.fromSnapshot(doc)).toList();

  heatmapRef = FirebaseFirestore.instance
      .collection('heatmap_drop')
      .where('route_id', isEqualTo: routeId)
      .where('timestamp', isGreaterThanOrEqualTo: start)
      .where('timestamp', isLessThanOrEqualTo: end);

  querySnapshot = await heatmapRef.get();
  var heatMapDataDropList = querySnapshot.docs.map((doc) => HeatMapData.fromSnapshot(doc)).toList();

  Future<List<String>> getAddressFromLatLngList(List<dynamic> locations) async {
    List<Future<String>> addressFutures = locations.map((location) => getAddressFromLatLngFuture(location.latitude, location.longitude)).toList();
    return await Future.wait(addressFutures);
  }

  // Convert collection data to a CSV format
  List<List<dynamic>> csvData1 = [
    ['Heatmap for Pickups from ${DateFormat('MM-dd-yyyy').format(start.toDate())} to ${DateFormat('MM-dd-yyyy').format(end.toDate())}, Route: ${JeepRoutes[routeId].name}', ' ', ' ', ' ', ' '],
    ['Heatmap ID', 'Location', 'Street', 'Passengers Taken', 'Timestamp'], // Replace with your field names
    ...heatMapDataRideList.map((data) => [data.heatmap_id, '${data.location.latitude}, ${data.location.longitude}', '', data.passenger_count, DateFormat('MM-dd-yyyy-HH:mm:ss').format(data.timestamp.toDate())]),[' ', ' ', ' ', ' ', ' '],
    ['Heatmap for Drop Offs from ${DateFormat('MM-dd-yyyy').format(start.toDate())} to ${DateFormat('MM-dd-yyyy').format(end.toDate())}, Route: ${JeepRoutes[routeId].name}', ' ', ' ', ' ', ' '],
    ['Heatmap ID', 'Location', 'Street', 'Passengers Dropped', 'Timestamp'],
    ...heatMapDataDropList.map((data) => [data.heatmap_id, '${data.location.latitude}, ${data.location.longitude}', '', data.passenger_count, DateFormat('MM-dd-yyyy-HH:mm:ss').format(data.timestamp.toDate())]),
  ];

  List<dynamic> locations = heatMapDataRideList.map((data) => data.location).toList();
  List<String> addresses = await getAddressFromLatLngList(locations);
  int prev = 0;

  for (int i = 0; i < addresses.length; i++) {
    csvData1[i + 2][2] = addresses[i];
    prev++;
  }

  locations = heatMapDataDropList.map((data) => data.location).toList();
  addresses = await getAddressFromLatLngList(locations);

  for (int i = 0; i < addresses.length; i++) {
    csvData1[prev + i + 5][2] = addresses[i];
  }

  String csvContent = const ListToCsvConverter().convert(csvData1);

  DateTime now = DateTime.now();
  String formattedDate = DateFormat('MM-dd-yyyy-HH-mm-ss').format(now);

  if(kIsWeb){
    final bytes = utf8.encode(csvContent);
    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);

    final anchor = html.document.createElement('a') as html.AnchorElement..href = url..style.display = 'none'..download = 'TransiTrack_heatmap_$formattedDate.csv';

    html.document.body!.children.add(anchor);

    anchor.click();

    html.Url.revokeObjectUrl(url);
  } else if (Platform.isAndroid){
    Directory generalDownloadDir = Directory('storage/emulated.0/Download');

    final File file = await (File('${generalDownloadDir.path}/TransiTrack_heatmap_ride_$formattedDate.csv').create());

    await file.writeAsString(csvContent);
  }
}