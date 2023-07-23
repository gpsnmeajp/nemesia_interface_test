import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:async/async.dart';
import 'package:flutter/foundation.dart';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:nostr/nostr.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

import 'nip07_mock.dart' if (dart.library.html) 'nip07_web.dart';

import 'repository_interfaces.dart';
part 'relay_repository.freezed.dart';

typedef SubscriptionId = String;
typedef RelayUrl = String;
typedef EventId = String;

@freezed
abstract class Subscription with _$Subscription {
  const factory Subscription({
    required SubscriptionId id,
    required Function(SubscriptionId) eoseCallback,
  }) = _Subscription;
}

@freezed
abstract class EventWithJson with _$EventWithJson {
  const factory EventWithJson({
    required Event event,
    required String json,
  }) = _EventWithJson;
}

@unfreezed
abstract class ReceivingEvents with _$ReceivingEvents {
  factory ReceivingEvents({
    required Map<RelayUrl, Map<EventId, EventWithJson>> eventsOnRelays,
    required DateTime lastReceived,
  }) = _ReceivingEvents;
}

@Freezed(makeCollectionsUnmodifiable: false)
abstract class EventWithRelays with _$EventWithRelays {
  const factory EventWithRelays({
    required EventWithJson event,
    required List<RelayUrl> relays,
  }) = _EventWithRelays;
}

class RelayRepository implements RelayRepositoryInterface {
  // シングルトン
  static final RelayRepository _instance = RelayRepository._();
  factory RelayRepository() => _instance;

  // 接続リレープール
  final Map<RelayUrl, WebSocketChannel> _webSocketChannelList = {};

  // 接続したいリレーリスト
  final List<RelayUrl> _relays = [
    "wss://relay-jp.nostr.wirednet.jp",
    "wss://yabu.me"
  ];

  // 秘密鍵(nullの場合、未格納のためNIP-07を使用する)
  Keychain? keychain;

  // イベント受信バッファ(サブスクID別、リレー別イベント)
  final Map<SubscriptionId, ReceivingEvents> _eventBuffer = {};

  // キャッシュ
  final Map<EventId, EventWithRelays> _eventCache = {};

  // サブスクリプションID - Event callback
  final Map<SubscriptionId, Subscription> _subscriptions = {};

  // 名前付きコンストラクタ(プライベート)
  RelayRepository._() {
    // 周期タイマー
    Timer.periodic(const Duration(seconds: 15), _onPeriodicTimer);
  }

  // 周期イベント処理
  void _onPeriodicTimer(Timer timer) async {
    // 接続状態チェックと、自動再接続
    _webSocketChannelList.forEach((r, w) {
      if (w.closeCode != null) {
        // 既存の接続を閉じる
        try {
          w.sink.close();
        } catch (e) {
          // Do noting
        }

        // 接続を開始する
        var s = WebSocketChannel.connect(Uri.parse(r));
        s.stream.listen((message) {
          // なにか受信した: 受信物はすべて同じところに流し込む
          _onWebsocketReceived(r, message);
        });
        // 接続管理する
        _webSocketChannelList[r] = s;
      }
    });
  }

  // 単発リクエストを実施
  Future<Map<EventId, EventWithRelays>?> _oneshotRequest(
      List<Filter> filters) async {
    debugPrint("[oneshotRequest] Start");
    var completer = Completer<Map<EventId, EventWithRelays>?>();
    var isEOSE = false;

    // リクエストを生成
    String subscriptionId = generate64RandomHexChars().substring(0, 32);
    debugPrint("[oneshotRequest]$subscriptionId");

    // 完了時 or タイムアウト処理を追加
    void onComplete() {
      // すでに完了済みの場合無視(期限切れタイマーによるもの)
      if (completer.isCompleted) {
        return;
      }

      // データを受信中であり、最後に受信してから100ms以内なら、追加で100ms待つ
      if (_eventBuffer[subscriptionId] != null &&
          (DateTime.now()
                  .difference(_eventBuffer[subscriptionId]!.lastReceived) <
              const Duration(milliseconds: 100))) {
        debugPrint(
            "[oneshotRequest] Contine: $subscriptionId ${_eventBuffer[subscriptionId]!.lastReceived}");
        Future.delayed(const Duration(milliseconds: 100), onComplete);
        return;
      }

      // サブスク解除
      // サブスクリプションを停止
      _subscriptions.remove(subscriptionId);
      _sendAllRelay(Close(subscriptionId).serialize());

      // 終了状態を判定
      if (_eventBuffer[subscriptionId] != null) {
        debugPrint(
            "[oneshotRequest] On data: $subscriptionId  ${_eventBuffer[subscriptionId]!.lastReceived} ${DateTime.now()} ${isEOSE.toString()}");
        // 最低一つは応答はあったので、対象の投稿を取り出す
        var eventsPerRelay = _eventBuffer[subscriptionId]!.eventsOnRelays;
        Map<EventId, EventWithRelays> events = {};

        // リレーごとの投稿を取り出し
        eventsPerRelay.forEach((relayUrl, eventsOfId) {
          // 同じIDは同じ内容なので内容チェックは不要
          eventsOfId.forEach((eventId, event) {
            if (!events.containsKey(eventId)) {
              // どのリレーからもまだ来ていない情報だった場合、格納
              events[eventId] = EventWithRelays(
                  event: event,
                  relays: List<RelayUrl>.from([relayUrl], growable: true));
            } else {
              // すでに到達済みの場合、リレー情報だけ追加
              events[eventId]!.relays.add(relayUrl);
            }
          });
        });

        // イベントキャッシュに格納
        events.forEach((eventId, event) {
          _eventCache[eventId] = event;
        });

        // 受信バッファから消去
        _eventBuffer.remove(subscriptionId);

        // 打ち上げ
        completer.complete(events);
        return;
      }

      // データがなかった時
      if (isEOSE) {
        // EOSEは来たがデータが1件もなかった(リレーに存在しないデータ)
        debugPrint("[oneshotRequest] No data");
        completer.complete(null);
      } else {
        // どのリレーからも応答がなかった(通信切断 or EOSE非対応リレーしかいない)
        debugPrint("[oneshotRequest] Timeout");
        completer.completeError("Timeout");
      }
    }

    // callbackを登録
    _subscriptions[subscriptionId] = Subscription(
      id: subscriptionId,
      eoseCallback: (String subscriptionId) {
        // EOSE
        debugPrint("[oneshotRequest] EOSE: $subscriptionId");
        isEOSE = true;
        // 100ms後に確定処理
        Future.delayed(const Duration(milliseconds: 100), () {
          onComplete();
        });
      },
    );

    // サブスクリプションを開始
    Request request = Request(subscriptionId, filters);
    _sendAllRelay(request.serialize());

    // 3秒後に強制タイムアウト
    Future.delayed(const Duration(seconds: 3), () {
      onComplete();
    });

    return completer.future;
  }

  // 接続済みWebsocketから何かを受け取った
  void _onWebsocketReceived(relayUrl, payload) async {
    // 文字列を受信した時
    if (payload is String) {
      // debugPrint('[onWebsocketReceived] Received event($relayUrl): $payload');

      // Web版ではEVENTは署名検証スキップする(負荷が非常に高いため)
      var data = jsonDecode(payload);
      if (data[0] == "EVENT") {
        Event e = Event.deserialize(data, verify: !kIsWeb);
        if (e.kind == 4) {
          // ignore: deprecated_member_use
          e = EncryptedDirectMessage(data);
        }

        //リレーバッファがない場合、作る
        if (_eventBuffer[e.subscriptionId!] == null) {
          _eventBuffer[e.subscriptionId!] =
              ReceivingEvents(eventsOnRelays: {}, lastReceived: DateTime.now());
        }
        //投稿のバッファがない場合、作る
        if (_eventBuffer[e.subscriptionId!]!.eventsOnRelays[relayUrl] == null) {
          _eventBuffer[e.subscriptionId!]!.eventsOnRelays[relayUrl] = {};
        }
        // イベントをリレー別バッファに詰める
        _eventBuffer[e.subscriptionId!]!.eventsOnRelays[relayUrl]![e.id] =
            EventWithJson(event: e, json: data[1]);
        _eventBuffer[e.subscriptionId!]!.lastReceived = DateTime.now();
        return;
      }
      debugPrint('[onWebsocketReceived] Received event($relayUrl): $payload');
      //デシリアライズと、署名検証
      Message m = Message.deserialize(payload);
      switch (m.type) {
        case "EVENT":
          // ここには来ない
          break;
        case "EOSE":
          // EOSE通知を取り出す
          SubscriptionId subscriptionId = jsonDecode(m.message as String)[0];
          // EOSEをイベントバッファ処理のトリガとする
          _subscriptions[subscriptionId]?.eoseCallback.call(subscriptionId);
          break;
        default:
          // NOTICE, エラーなど
          debugPrint('Received event($relayUrl): $payload');
          break;
      }
    }
  }

  // すべてのリレーに送信する
  void _sendAllRelay(dynamic data) {
    debugPrint("Send");
    _webSocketChannelList.forEach((r, w) {
      w.sink.add(data);
    });
  }

  // 状況に応じて取得手段を使い分けて、公開鍵を取得
  Future<Pubkey?> getMyPubkey() async {
    if (keychain == null) {
      return await Nip07.getPublicKey();
    } else {
      return keychain?.public;
    }
  }

  // 状況に応じて署名手段を使い分けて、署名して送信
  Future<void> signAndSend(
      int kind, List<List<String>> tags, String content) async {
    Event event = Event.partial();
    event.createdAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    event.content = content;
    event.kind = kind;
    event.tags = tags;

    if (keychain == null) {
      Nip07Event nip07 = Nip07Event(
        created_at: event.createdAt,
        pubkey: event.pubkey,
        content: event.content,
        id: "",
        kind: event.kind,
        sig: "",
        tags: event.tags,
      );

      event.pubkey = (await Nip07.getPublicKey())!;
      var result = await Nip07.signEvent(nip07);
      event.id = result!.id;
      event.sig = result.sig;
    } else {
      event.pubkey = keychain!.public;
      event.id = event.getEventId();
      event.sig = event.getSignature(keychain!.private);
    }

    if (!event.isValid()) {
      throw Error();
    }

    _sendAllRelay(event.serialize());
  }

  // -----------------------

  @override
  void connect() {
    // すでに接続済みなら全部切断する
    _webSocketChannelList.forEach((r, w) {
      w.sink.close();
    });
    _webSocketChannelList.clear();

    // 接続を開始する
    for (var r in _relays) {
      var w = WebSocketChannel.connect(Uri.parse(r));
      w.stream.listen((message) {
        // なにか受信した: 受信物はすべて同じところに流し込む
        _onWebsocketReceived(r, message);
      });
      // 接続管理する
      _webSocketChannelList[r] = w;
    }
    debugPrint("Connect");
  }

  @override
  List<String> getRelay() {
    return _relays;
  }

  @override
  void setRelay(List<String> relays) {
    _relays.clear();
    _relays.addAll(relays);
  }

  @override
  void setSelfKey(String? privateKey) {
    if (privateKey == null) {
      // NIP-7にする予定
      throw UnimplementedError();
    }
    var privKey = Nip19.decodePrivkey(privateKey);
    if (privKey != "") {
      keychain = Keychain(privKey);
    } else {
      throw ArgumentError("not private key");
    }
  }

  @override
  Future<List<TextNote>> getTextNotes({
    List<String>? ids,
    List<String>? authers,
    List<String>? e,
    List<String>? p,
    DateTime? since,
    DateTime? until,
    int? limit,
  }) async {
    var events = await _oneshotRequest([
      Filter(
        kinds: [1],
        ids: ids,
        authors: authers,
        e: e,
        p: p,
        since: since != null ? since.millisecondsSinceEpoch ~/ 1000 : null,
        until: until != null ? until.millisecondsSinceEpoch ~/ 1000 : null,
        limit: limit,
      )
    ]);

    // データがある
    if (events != null) {
      // autherを抽出
      List<String> authers = List.empty(growable: true);
      events.forEach((EventId id, EventWithRelays event) {
        authers.add(event.event.event.pubkey);
      });
      var metadatas = await getMetadatas(authers);

      // Note本体を取得
      List<TextNote> notes = List.empty(growable: true);
      events.forEach((EventId id, EventWithRelays event) {
        var e = event.event;
        String? nip36;
        try {
          nip36 = e.event.tags
              .firstWhere((element) => element[0] == "content-warning")[1];
        } catch (e) {
          // Do noting
        }
        try {
          var note = TextNote(
            // --- 生データ
            rawJson: e.json,
            relays: event.relays,
            // --- 基本情報
            id: Nip19.encodeNote(e.event.id), // NIP-19
            pubkey: Nip19.encodePubkey(e.event.pubkey), // NIP-19
            createdAt:
                DateTime.fromMillisecondsSinceEpoch(e.event.createdAt * 1000),
            // --- TextNote基本情報
            content: e.event.content,
            tags: e.event.tags,
            // --- TextNote付属情報
            nip36: nip36,
            autherMetadata: metadatas[e.event.pubkey],
          );
          notes.add(note);
        } catch (e) {
          debugPrint("[getTextNotes] $e");
        }
      });

      return notes;
    } else {
      // データがない
      return [];
    }
  }

  @override
  Future<List<Pubkey>> getContactList(String pubkey) {
    // TODO: implement getContactList
    throw UnimplementedError();
  }

  @override
  Future<Map<Pubkey, Metadata>> getMetadatas(List<String>? pubkeys) async {
    var mypubkey = await getMyPubkey();
    if (mypubkey == null) {
      return {};
    }
    pubkeys ??= [mypubkey];
    var autherevents = await _oneshotRequest([
      Filter(
        kinds: [0],
        authors: pubkeys,
      )
    ]);

    var output = <Pubkey, Metadata>{};
    autherevents?.forEach((EventId id, EventWithRelays e) {
      try {
        Map<String, dynamic> data = jsonDecode(e.event.event.content);
        Metadata metadata = Metadata(
          // --- 生データ
          rawJson: e.event.json,
          relays: e.relays,
          // --- 基本情報
          id: Nip19.encodeNote(e.event.event.id), // NIP-19
          pubkey: Nip19.encodePubkey(e.event.event.pubkey), // NIP-19
          createdAt: DateTime.fromMillisecondsSinceEpoch(
              e.event.event.createdAt * 1000),
          // --- Metadata情報(基本)
          name: data["name"],
          picture: data["picture"],
          about: data["about"],
          // --- Metadata情報(応用)
          banner: data["banner"],
          website: data["website"],
          nip05: data["nip05"],
          lud16: data["lud16"],
          displayName: data["display_name"],
        );
        output[e.event.event.pubkey] = metadata;
      } catch (e) {
        debugPrint("[getMetadatas] $e");
      }
    });
    return output;
  }

  @override
  Future<List<RecommendServer>> getRecommendServer(String pubkey) {
    // TODO: implement getRecommendServer
    throw UnimplementedError();
  }

  @override
  Future<void> postMyMetadata(Metadata metadata) {
    // TODO: implement postMyMetadata
    throw UnimplementedError();
  }

  @override
  Future<void> postMyTextNote(String content, List<List<String>> tags) {
    // TODO: implement postMyTextNote
    throw UnimplementedError();
  }

  @override
  Future<void> postReaction(String noteId, String? reaction, String? emojiUrl) {
    // TODO: implement postReaction
    throw UnimplementedError();
  }

  @override
  Future<void> postRepost(TextNote textNote) {
    // TODO: implement postRepost
    throw UnimplementedError();
  }
}
