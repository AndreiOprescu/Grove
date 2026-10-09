enum ItemType { task, event, note }

class ItemRef {
  const ItemRef(this.type, this.id);

  final ItemType type;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is ItemRef && other.type == type && other.id == id;

  @override
  int get hashCode => Object.hash(type, id);

  @override
  String toString() => '${type.name}:$id';
}

enum LinkOrigin { parsed, manual }

class LinkRecord {
  const LinkRecord({
    required this.src,
    required this.dst,
    required this.origin,
  });

  final ItemRef src;
  final ItemRef dst;
  final LinkOrigin origin;

  @override
  bool operator ==(Object other) =>
      other is LinkRecord &&
      other.src == src &&
      other.dst == dst &&
      other.origin == origin;

  @override
  int get hashCode => Object.hash(src, dst, origin);
}
