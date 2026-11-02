import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/process/service_controller.dart';
import '../features/manga/controller/queue_controller.dart';

final pairingTokenProvider = AsyncNotifierProvider<PairingTokenNotifier, String?>(PairingTokenNotifier.new);

class PairingTokenNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async => ref.watch(serviceSupervisorProvider)?.token;

  Future<String?> refreshToken() async {
    state = const AsyncValue.loading();
    try {
      final token = await ref.read(mangaSvcClientProvider).refreshPairingToken();
      final supervisor = ref.read(serviceSupervisorProvider);
      if (supervisor != null) supervisor.token = token;
      state = AsyncValue.data(token);
      return token;
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      return null;
    }
  }
}
