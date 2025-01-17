import 'dart:convert';
import 'dart:math' show atan2, cos, pi, sin, sqrt;
import 'package:dotenv/dotenv.dart';
import 'package:http/http.dart' as http;

import 'package:backend/controller/mapObjectId.dart';
import 'package:backend/db/database_connection.dart';
import 'package:data_sources/data_sources.dart';
import 'package:exceptions/exceptions.dart';
import 'package:models/models.dart';
import 'package:mongo_dart/mongo_dart.dart';

final env = DotEnv(includePlatformEnvironment: true)..load(['variables.env']);

/// {@template report_mileage_data_source}
/// Report Mileage data source implementation for backend
/// {@endtemplate}
class ReportMileageDataSourceImpl extends ReportMileageDataSource {
  /// {@macro vehicle_data_source_impl}
  ReportMileageDataSourceImpl({
    required DatabaseConnection databaseConnection,
  }) : _databaseConnection = databaseConnection;
  final DatabaseConnection _databaseConnection;

  /// Get distance using google maps
  Future<double> getDistanceByGoogleMaps(
    String origin,
    String destination,
  ) async {
    final apiKey = env['GOOGLE_MAPS_API_KEY'] ?? '';
    // Replace with your API key

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json?origin=$origin&destination=$destination&mode=driving&key=$apiKey',
    );

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final distance = data['routes'][0]['legs'][0]['distance']['value'] as int;
      return distance / 1000;
    } else {
      throw Exception('Failed to fetch distance');
    }
  }

  @override
  Future<ReportMileage> createReport(CreateReportDto data) async {
    try {
      final collection = _databaseConnection.db.collection('reportMileage');
      final hasGpsSignal = data.hasGpsSignal;
      var dataInput = data;
      print('Data received createReport: ${data.toJson()}');

      if (!hasGpsSignal) {
        try {
          // Calculate distance if no GPS signal
          final lastReport = await getLastReportOfVehicle(data.vehicle);
          print('Last report geolocation ${lastReport.geolocation}');
          print('Current report geolocation ${data.geolocation}');
          final lastReportGeo = lastReport.geolocation;
          final currentGeo = data.geolocation;
          final distance = await getDistanceByGoogleMaps(
            '${lastReportGeo?.lat},${lastReportGeo?.long}',
            '${currentGeo?.lat},${currentGeo?.long}',
          );

          // calculateDistance(lastReport.geolocation, data.geolocation);
          print('Distance between lastReport and current $distance');
          dataInput = dataInput.copyWith(
            mileage: data.mileage + (distance.toInt()),
          );
        } catch (e) {
          print('Error calculating distance in offline mode $e');
        } // Add calculated distance to mileage
      }

      final result = await collection.insertOne(
        {
          'vehicle': dataInput.vehicle,
          'mileage': dataInput.mileage,
          'channel': dataInput.channel,
          'hasGpsSignal': hasGpsSignal,
          'device': dataInput.device,
          'geolocation': dataInput.geolocation?.toJson(),
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        },
      );
      print('Result ${result.ok}');

      final document = result.document ?? {};

      final reportId = mapObjectId<String>(document['_id']);

      if (reportId.isLeft) {
        throw InternalServerException(
          'Unexpected error: ${reportId.left.message}',
        );
      }
      document['_id'] = reportId.right;

      final report = ReportMileage.fromJson(document);
      return report;
    } on HttpException {
      rethrow;
    } catch (e, s) {
      throw InternalServerException('Unexpected error: $e, $s');
    } finally {}
  }

  @override
  Future<OperationResultDto> deleteReport(String id) async {
    try {
      final collection = _databaseConnection.db.collection('reportMileage');
      final result =
          await collection.deleteOne(where.id(ObjectId.fromHexString(id)));

      return OperationResultDto(
        success: result.success,
        message: result.errmsg,
      );
    } on HttpException {
      rethrow;
    } catch (e) {
      throw InternalServerException('Unexpected error: $e');
    } finally {}
  }

  @override
  Future<List<ReportMileage>> getAllReports() async {
    try {
      final collection = _databaseConnection.db.collection('reportMileage');
      final result = await collection.find().toList();

      final reports = result.map((tagDocument) {
        final id = mapObjectId<String>(tagDocument['_id']);

        if (id.isLeft) {
          throw InternalServerException('Unexpected error: ${id.left.message}');
        }

        tagDocument['_id'] = id.right;
        try {
          return ReportMileage.fromJson(tagDocument);
        } catch (e, s) {
          print(s);
          rethrow;
        }
      }).toList();

      return reports;
    } on HttpException {
      rethrow;
    } catch (e) {
      throw InternalServerException('Unexpected error: $e');
    } finally {}
  }

  @override
  Future<List<ReportMileage>> getAllReportsByVehicle(String vehicleId) async {
    try {
      final collection = _databaseConnection.db.collection('reportMileage');
      final result = await collection
          .find(where.eq('vehicle', vehicleId).sortBy('createdAt'))
          .toList();

      final reports = result.map((tagDocument) {
        final id = mapObjectId<String>(tagDocument['_id']);
        if (id.isLeft) {
          throw InternalServerException('Unexpected error: ${id.left.message}');
        }
        tagDocument['_id'] = id.right;
        return ReportMileage.fromJson(tagDocument);
      }).toList();
      return reports;
    } on HttpException {
      rethrow;
    } catch (e) {
      throw InternalServerException('Unexpected error: $e');
    } finally {}
  }

  @override
  Future<ReportMileage> getLastReportOfVehicle(String vehicleId) async {
    try {
      final collection = _databaseConnection.db.collection('reportMileage');

      final result = await collection.findOne(
        where.eq('vehicle', vehicleId).sortBy(
              'createdAt',
              descending: true,
            ),
      );
      final document = result ?? {};

      if (document.isEmpty) {
        throw NotFoundException(
          'Not found report for $vehicleId',
        );
      }

      final reportId = mapObjectId<String>(document['_id']);
      if (reportId.isLeft) {
        throw InternalServerException(
          'Unexpected error: ${reportId.left.message}',
        );
      }
      document['_id'] = reportId.right;

      final report = ReportMileage.fromJson(document);
      return report;
    } on HttpException {
      rethrow;
    } catch (e) {
      throw InternalServerException('Unexpected error: $e');

      //
    } finally {}
  }

  @override
  Future<ReportMileage> getReportById(String id) async {
    try {
      final collection = _databaseConnection.db.collection('reportMileage');
      final result =
          await collection.findOne(where.id(ObjectId.fromHexString(id)));
      final document = result ?? {};

      if (document.isEmpty) {
        throw NotFoundException(
          'Not found report $id',
        );
      }

      final vehicleId = mapObjectId<String>(document['_id']);
      if (vehicleId.isLeft) {
        throw InternalServerException(
          'Unexpected error: ${vehicleId.left.message}',
        );
      }
      document['_id'] = vehicleId.right;

      final report = ReportMileage.fromJson(document);
      return report;
    } on HttpException {
      rethrow;
    } catch (e) {
      throw InternalServerException('Unexpected error: $e');
    } finally {}
  }

  int calculateDistance(Geolocation? from, Geolocation? to) {
    if (from == null || to == null) {
      return 0; // Handle null values
    }

    const earthRadius = 6371000.0; // Earth's radius in meters

    final lat1 = from.lat * pi / 180;
    final lon1 = from.long * pi / 180;
    final lat2 = to.lat * pi / 180;
    final lon2 = to.long * pi / 180;

    final dLat = lat2 - lat1;
    final dLon = lon2 - lon1;

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 *
        atan2(
          sqrt(a),
          sqrt(
            1 - a,
          ),
        );

    final distance = earthRadius * c;

    return (distance / 1000).toInt();
  }
}
