import 'dart:math' as math;
import 'dart:async';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flame/sprite.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:tiled/tiled.dart';

/// Tiled represents all flips and rotation using three possible flips: horizontal, vertical and diagonal.
/// This class converts that representation to a simpler one, that uses one angle (with pi/2 steps) and two flips (H or V).
/// More reference: https://doc.mapeditor.org/en/stable/reference/tmx-map-format/#tile-flipping
class _SimpleFlips {
  /// The angle (in steps of pi/2 rads), clockwise, around the center of the tile.
  final int angle;

  /// Whether to flip across a central vertical axis (passing through the center).
  final bool flipH;

  /// Whether to flip across a central horizontal axis (passing through the center).
  final bool flipV;

  _SimpleFlips(this.angle, this.flipH, this.flipV);

  /// This is the conversion from the truth table that I drew.
  factory _SimpleFlips.fromFlips(Flips flips) {
    int angle;
    bool flipV, flipH;

    if (!flips.diagonally && !flips.vertically && !flips.horizontally) {
      angle = 0;
      flipV = false;
      flipH = false;
    } else if (!flips.diagonally && !flips.vertically && flips.horizontally) {
      angle = 0;
      flipV = false;
      flipH = true;
    } else if (!flips.diagonally && flips.vertically && !flips.horizontally) {
      angle = 0;
      flipV = true;
      flipH = false;
    } else if (!flips.diagonally && flips.vertically && flips.horizontally) {
      angle = 2;
      flipV = false;
      flipH = false;
    } else if (flips.diagonally && !flips.vertically && !flips.horizontally) {
      angle = 1;
      flipV = false;
      flipH = true;
    } else if (flips.diagonally && !flips.vertically && flips.horizontally) {
      angle = 1;
      flipV = false;
      flipH = false;
    } else if (flips.diagonally && flips.vertically && !flips.horizontally) {
      angle = 3;
      flipV = false;
      flipH = false;
    } else if (flips.diagonally && flips.vertically && flips.horizontally) {
      angle = 1;
      flipV = true;
      flipH = false;
    } else {
      // this should be exhaustive
      throw 'Invalid combination of booleans: $flips';
    }

    return _SimpleFlips(angle, flipH, flipV);
  }
}

/// This component renders a tile map based on a TMX file from Tiled.
class Tiled {
  String filename;
  late TiledMap map;
  Image? image;
  Map<String?, SpriteBatch> batches = <String, SpriteBatch>{};
  Future? future;
  bool _loaded = false;
  Size destTileSize;

  static Paint paint = Paint()..color = Colors.white;

  /// Creates this Tiled with the filename (for the tmx file resource)
  /// and destTileSize is the tile size to be rendered (not the tile size in the texture, that one is configured inside Tiled).
  Tiled(this.filename, this.destTileSize) {
    future = _load();
  }

  Future _load() async {
    map = await _loadMap();
    String? src = map.tilesets[0].image!.source;
    if (src != null) {
      image = await Flame.images.load(src);
      batches = await _loadImages(map);
      generate();
      _loaded = true;
    }
  }

  Future<TiledMap> _loadMap() {
    return Flame.bundle.loadString('assets/tiles/$filename').then((contents) {
      return TileMapParser.parseTmx(contents);
    });
  }

  Future<Map<String?, SpriteBatch>> _loadImages(TiledMap map) async {
    final Map<String?, SpriteBatch> result = {};
    await Future.forEach(map.tilesets, (Tileset tileset) async {
      await Future.forEach(tileset.tiles, (Tile tmxImage) async {
        TiledImage? img = tmxImage.image;
        if (img != null) {
          String? src = img.source;
          if (src != null) {
            result[src] = await SpriteBatch.load(src);
          }
        }
      });
    });
    return result;
  }

  /// Generate the sprite batches from the existing tilemap.
  void generate() {
    for (var batch in batches.keys) {
      batches[batch]!.clear();
    }
    _drawTiles(map);
  }

  void _drawTiles(TiledMap map) {
    map.layers.where((layer) => layer.visible).forEach((Layer layer) {
      var tileLayer = layer as TileLayer;
      var tileData = tileLayer.tileData;
      if (tileData != null) {
        tileData.forEach((tileRow) {
          tileRow.forEach((tile) {
            if (tile.tile == 0) {
              return;
            }
            Tile t = map.tileByGid(tile.tile);
            TiledImage? img = t.image;
            if (img != null) {
              final batch = batches[img.source]!;
              final rect = Tileset().computeDrawRect(t);

              final src = Rect.fromLTWH(
                rect.left.toDouble(),
                rect.top.toDouble(),
                rect.width.toDouble(),
                rect.height.toDouble(),
              );

              final flips = _SimpleFlips.fromFlips(tile.flips);
              final Size tileSize = destTileSize;

              batch.add(
                source: src,
                offset: Vector2(
                  rect.left * tileSize.width +
                      (tile.flips.horizontally ? tileSize.width : 0),
                  rect.top * tileSize.height +
                      (tile.flips.vertically ? tileSize.height : 0),
                ),
                rotation: flips.angle * math.pi / 2,
                scale: tileSize.width / rect.width,
              );
            }
          });
        });
      }
    });
  }

  bool loaded() => _loaded;

  void render(Canvas c) {
    if (!loaded()) {
      return;
    }

    batches.forEach((_, batch) {
      batch.render(c);
    });
  }

  /// This returns an object group fetch by name from a given layer.
  /// Use this to add custom behaviour to special objects and groups.
  Future<ObjectGroup> getObjectGroupFromLayer(String name) {
    return future!.then((onValue) {
      var g = map.layers
          .firstWhere((layer) => layer is ObjectGroup && layer.name == name);
      return g as ObjectGroup;
    });
  }
}
