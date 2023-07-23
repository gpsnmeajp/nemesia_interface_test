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
    print("Connect");
    _relayRepository.connect();
    Future.sync(() async {
      var notes = await _relayRepository.getTextNotes(limit: 10);
      for (var note in notes) {
        debugPrint("---");
        debugPrint(note.toString());
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
