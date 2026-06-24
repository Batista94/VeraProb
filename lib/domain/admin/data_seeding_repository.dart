abstract class DataSeedingRepository {
  Future<void> seedDrivers(String organizationId);
  Future<void> seedRoutes(String organizationId);
  Future<void> seedHistoricalData(String organizationId);
  Future<void> seedActiveSanctions(String organizationId);
  Future<void> seedPhase9(String organizationId);
  Future<void> seedCsvData(String organizationId);
}
