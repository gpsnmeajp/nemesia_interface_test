import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flutter/foundation.dart';
part 'repository_interfaces.freezed.dart';
part 'repository_interfaces.g.dart';
// flutter pub run build_runner build --delete-conflicting-outputs
// flutter run -d chrome

/*
拡張機能を試す方法
https://qiita.com/koji4104/items/65bba670f0519a23b9f6
flutter_tools.stampを削除

Flutter SDKのchrome.dartを開き

--user-data-dir=${userDataDir.path}　を自分のプロファイルに変更
--disable-extensions　をコメントアウト
profile-directoryを追加

*/

@freezed
class Nip07Event with _$Nip07Event {
  const factory Nip07Event({
    required String id, // HEX
    required String pubkey, //HEX
    // ignore: non_constant_identifier_names
    required int created_at,
    required int kind,
    required List<List<String>> tags,
    required String content,
    required String sig,
  }) = _Nip07Event;
  factory Nip07Event.fromJson(Map<String, Object?> json) =>
      _$Nip07EventFromJson(json);
}

@freezed
abstract class TextNote with _$TextNote {
  const factory TextNote({
    // --- 生データ
    required String rawJson,
    required List<String> relays,
    // --- 基本情報
    required String id, // NIP-19
    required String pubkey, //NIP-19
    required DateTime createdAt,
    // --- TextNote基本情報
    required String content,
    required List<List<String>> tags,
    // --- TextNote付属情報
    required String? nip36,
    required Metadata? autherMetadata,
  }) = _TextNote;
}

@freezed
abstract class Metadata with _$Metadata {
  const factory Metadata({
    // --- 生データ
    required String rawJson,
    required List<String> relays,
    // --- 基本情報
    required String id, // NIP-19
    required String pubkey, //NIP-19
    required DateTime createdAt,
    // --- Metadata情報(基本)
    required String name,
    required String picture,
    required String about,
    // --- Metadata情報(応用)
    required String banner,
    required String website,
    required String nip05,
    required String lud16,
    required String displayName,
  }) = _Metadata;
}

/*
{
    "banner": "https://www.gravatar.com/avatar/19606b92a428ca0fed7fe5291bcfd865?",
    "website": "https://ja.gravatar.com/gpsnmeajp",
    "nip05": "_@sabowl.sakura.ne.jp",
    "picture": "https://www.gravatar.com/avatar/19606b92a428ca0fed7fe5291bcfd865?",
    "lud16": "nervoustent17@walletofsatoshi.com",
    "display_name": "Segment(gpsnmeajp)",
    "about": "日本ユーザーを探すには: Nostr検索ポータル https://nostr.hoku.in が便利です。n---nEVMC4UやVaNiiMenu、VMCProtocolなど作ってました。フォロー解除はお気軽に。ツールのサポートは各discordへn---n「ハマりすぎる」ので不定期にいなくなります。お手数ですが反応がない時は別の連絡手段を使用してください。nまた、DMなどは気づかないことがあります。",
    "name": "gpsnmeajp"
}
*/

@freezed
abstract class Reaction with _$Reaction {
  const factory Reaction({
    // --- 生データ
    required String rawJson,
    required List<String> relays,
    // --- 基本情報
    required String id, // NIP-19
    required String pubkey, //NIP-19
    required DateTime createdAt,
    // --- Reaction情報
    required String content,
    required String? emojiUrl,
    required String targetId,
    required String targetPubkey,
  }) = _Reaction;
}

@freezed
abstract class RecommendServer with _$RecommendServer {
  const factory RecommendServer({
    required String address,
    required bool read,
    required bool write,
  }) = _RecommendServer;
}

// リレーから情報を取ってくるためのIF
class RelayRepositoryInterface {
  // リレーに接続・再接続する
  void connect() {
    throw UnimplementedError();
  }

  // リレーを取得する
  List<String> getRelay() {
    throw UnimplementedError();
  }

  // リレーを更新する。nullの場合はNIP-07を使用しようとする。
  void setRelay(List<String> relays) {
    throw UnimplementedError();
  }

  // 自己のkeyをセットする。nullの場合はNIP-07を使用しようとする。
  // NIP-19
  void setSelfKey(String? secretKey) {
    throw UnimplementedError();
  }

  // 指定のメモ(あるいはタイムライン)を取得する
  // NIP-01, kind 1
  Future<List<TextNote>> getTextNotes(
    List<String>? ids, // NIP-19
    List<String>? authers, //NIP-19
    List<String>? e,
    List<String>? p,
    DateTime? since,
    DateTime? until,
    int? limit,
  ) async {
    throw UnimplementedError();
  }

  // 指定のプロフィールを取得する(認識できない情報は生jsonに含まれる)
  // NIP-01, kind 0
  // pubkey: NIP-19
  Future<List<Metadata>> getMetadatas(List<String>? pubkeys) async {
    throw UnimplementedError();
  }

  // 指定のフォローリストを取得する
  // NIP-02, kind 3
  // pubkey: NIP-19
  Future<List<Metadata>> getContactList(String pubkey) async {
    throw UnimplementedError();
  }

  // 指定の推奨リレーリストを取得する
  // NIP-01, kind 2
  // pubkey: NIP-19
  Future<List<RecommendServer>> getRecommendServer(String pubkey) async {
    throw UnimplementedError();
  }

  // メモを投稿する
  // NIP-01, kind 1
  Future<void> postMyTextNote(String content, List<List<String>> tags) async {
    throw UnimplementedError();
  }

  // 自己プロフィールを投稿する(認識できない情報は生jsonに含まれているためそれを使用する)
  // NIP-01, kind 0
  Future<void> postMyMetadata(Metadata metadata) async {
    throw UnimplementedError();
  }

  // リアクションを投稿する
  // NIP-25, kind 7
  // noteId: NIP-19
  Future<void> postReaction(
      String noteId, String? reaction, String? emojiUrl) async {
    throw UnimplementedError();
  }

  // リポストを投稿する
  // NIP-18, kind 6
  Future<void> postRepost(TextNote textNote) async {
    throw UnimplementedError();
  }
}

@freezed
abstract class OPGMetaData with _$OPGMetaData {
  const factory OPGMetaData({
    required String title,
    required Uint8List image,
  }) = _OPGMetaData;
}

// OGPメタ情報を取得するためのIF
class OGPMetadataInterface {
  // OGP Metadataを取得します(キャッシュあり)
  Future<OPGMetaData> getMetaDataFromURL(String url) async {
    throw UnimplementedError();
  }
}

// ネットワーク上から画像を取得するためのIF
class FetchImageInterface {
  // ネットワーク上から画像を取得します(キャッシュあり)
  Future<Uint8List> getImageFromURL(String url) async {
    throw UnimplementedError();
  }
}