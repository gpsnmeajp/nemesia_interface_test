import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'relay_repository.dart';

void main() {
  runApp(ChangeNotifierProvider(
      create: (_) => Model(), lazy: false, child: const MyApp()));
}

class Model extends ChangeNotifier {
  final RelayRepository _relayRepository = RelayRepository();
  Model() {
    print("[Model] Connect");
    Future.sync(() async {
      await _relayRepository.connect();

      // フォロー取得
      var pubkeys = await _relayRepository
          .getContactList(await _relayRepository.getMyPubkey() ?? "");
      for (var note in pubkeys) {
        debugPrint(note.toString());
      }
      debugPrint("↓フォロー");
      var notes =
          await _relayRepository.getTextNotes(limit: 10, authers: pubkeys);
      for (var note in notes) {
        debugPrint("---");
        debugPrint(
            "${note.autherMetadata?.displayName ?? ""}: ${note.content}");
      }
      debugPrint("↓グローバル");
      var notesg = await _relayRepository.getTextNotes(limit: 10);
      for (var note in notesg) {
        debugPrint("---");
        debugPrint(
            "${note.autherMetadata?.displayName ?? ""}: ${note.content}");
      }
    });
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'Flutter Demo',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: Scaffold(body: Text("Test")));
  }
}
