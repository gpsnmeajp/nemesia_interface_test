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
      late var x;
      for (var note in notes) {
        debugPrint("---");
        debugPrint(
            "${note.autherMetadata?.displayName ?? ""}: ${note.content} ${note.rawJson}");
        x = note;
      }
      await _relayRepository.postRepost(x);
      debugPrint("↓グローバル");
      var notesg = await _relayRepository.getTextNotes(limit: 10);
      for (var note in notesg) {
        debugPrint("---");
        debugPrint(
            "${note.autherMetadata?.displayName ?? ""}: ${note.content}");
      }

      //await _relayRepository.postMyTextNote("content", []);
      /*
      await _relayRepository.postReaction(
          pubkey:
              "npub1yg6m89jp5t3w64e8n2nyd8vezt3gc8c05jylleht9v0x30zlx8fqqsydgh",
          noteId:
              "note1t5f2dnr07csn7wk2e59exjr8unyksshkd6nv8gcrtc8zchgrru5sx6s8tl",
          reaction: ":soapbox:",
          emojiUrl: "https://gleasonator.com/emoji/Gleasonator/soapbox.png");
          */
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
