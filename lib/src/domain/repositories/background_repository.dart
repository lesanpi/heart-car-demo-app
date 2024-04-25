abstract class IBackgroundRepository {
  const IBackgroundRepository();

  Future<bool> isEnabled();

  Future<void> initService();

  Future<void> requestPermissions();
}
