import '../models/sns_service.dart';

abstract class ScraperService {
  SnsService get service;
  String get scrapingScript;
}
