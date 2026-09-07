/// JSON の「形」だけを取り出す。
///
/// 新しい API に合わせてパーサーを書くには、どのキーに何が入っているかを
/// 知る必要がある。ただし DM の応答をそのままログに落とすと本文が残る。
/// ここではキー名と型・件数だけを出し、**値は一切出さない**。
///
/// 文字列は長さだけ、数値は桁が分かる程度に丸める。id らしき数値も
/// そのままでは出さない。
String jsonShape(Object? node, {int maxDepth = 7, int maxKeys = 40}) {
  final buf = StringBuffer();
  _write(buf, node, 0, maxDepth, maxKeys);
  return buf.toString();
}

void _write(StringBuffer buf, Object? node, int depth, int maxDepth,
    int maxKeys) {
  if (depth > maxDepth) {
    buf.write('…');
    return;
  }
  if (node == null) {
    buf.write('null');
  } else if (node is String) {
    buf.write('str(${node.length})');
  } else if (node is bool) {
    buf.write('bool');
  } else if (node is int) {
    buf.write('int(${node.toString().length}桁)');
  } else if (node is double) {
    buf.write('double');
  } else if (node is List) {
    if (node.isEmpty) {
      buf.write('[]');
      return;
    }
    // 要素は同じ形の繰り返しなので、先頭 1 件だけ見れば足りる
    buf.write('[${node.length}件 ');
    _write(buf, node.first, depth + 1, maxDepth, maxKeys);
    buf.write(']');
  } else if (node is Map) {
    final keys = node.keys.map((k) => '$k').toList()..sort();
    buf.write('{');
    var i = 0;
    for (final k in keys) {
      if (i >= maxKeys) {
        buf.write(' …他${keys.length - maxKeys}キー');
        break;
      }
      if (i > 0) buf.write(', ');
      buf.write('$k: ');
      _write(buf, node[k], depth + 1, maxDepth, maxKeys);
      i++;
    }
    buf.write('}');
  } else {
    buf.write(node.runtimeType.toString());
  }
}
