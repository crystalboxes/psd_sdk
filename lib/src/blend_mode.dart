import 'package:psd_sdk/src/key.dart';

enum BlendMode {
  /// Key = "pass"
  PASS_THROUGH,

  /// Key = "norm"
  NORMAL,

  /// Key = "diss"
  DISSOLVE,

  /// Key = "dark"
  DARKEN,

  /// Key = "mul "
  MULTIPLY,

  /// Key = "idiv"
  COLOR_BURN,

  /// Key = "lbrn"
  LINEAR_BURN,

  /// Key = "dkCl"
  DARKER_COLOR,

  /// Key = "lite"
  LIGHTEN,

  /// Key = "scrn"
  SCREEN,

  /// Key = "div "
  COLOR_DODGE,

  /// Key = "lddg"
  LINEAR_DODGE,

  /// Key = "lgCl"
  LIGHTER_COLOR,

  /// Key = "over"
  OVERLAY,

  /// Key = "sLit"
  SOFT_LIGHT,

  /// Key = "hLit"
  HARD_LIGHT,

  /// Key = "vLit"
  VIVID_LIGHT,

  /// Key = "lLit"
  LINEAR_LIGHT,

  /// Key = "pLit"
  PIN_LIGHT,

  /// Key = "hMix"
  HARD_MIX,

  /// Key = "diff"
  DIFFERENCE,

  /// Key = "smud"
  EXCLUSION,

  /// Key = "fsub"
  SUBTRACT,

  /// Key = "fdiv"
  DIVIDE,

  /// Key = "hue "
  HUE,

  /// Key = "sat "
  SATURATION,

  /// Key = "colr"
  COLOR,

  /// Key = "lum "
  LUMINOSITY,

  UNKNOWN
}

/// Converts a given key to the corresponding BlendMode.
BlendMode blendModeKeyToEnum(int key) {
  if (key == keyValue('pass')) {
    return BlendMode.PASS_THROUGH;
  } else if (key == keyValue('norm')) {
    return BlendMode.NORMAL;
  } else if (key == keyValue('diss')) {
    return BlendMode.DISSOLVE;
  } else if (key == keyValue('dark')) {
    return BlendMode.DARKEN;
  } else if (key == keyValue('mul ')) {
    return BlendMode.MULTIPLY;
  } else if (key == keyValue('idiv')) {
    return BlendMode.COLOR_BURN;
  } else if (key == keyValue('lbrn')) {
    return BlendMode.LINEAR_BURN;
  } else if (key == keyValue('dkCl')) {
    return BlendMode.DARKER_COLOR;
  } else if (key == keyValue('lite')) {
    return BlendMode.LIGHTEN;
  } else if (key == keyValue('scrn')) {
    return BlendMode.SCREEN;
  } else if (key == keyValue('div ')) {
    return BlendMode.COLOR_DODGE;
  } else if (key == keyValue('lddg')) {
    return BlendMode.LINEAR_DODGE;
  } else if (key == keyValue('lgCl')) {
    return BlendMode.LIGHTER_COLOR;
  } else if (key == keyValue('over')) {
    return BlendMode.OVERLAY;
  } else if (key == keyValue('sLit')) {
    return BlendMode.SOFT_LIGHT;
  } else if (key == keyValue('hLit')) {
    return BlendMode.HARD_LIGHT;
  } else if (key == keyValue('vLit')) {
    return BlendMode.VIVID_LIGHT;
  } else if (key == keyValue('lLit')) {
    return BlendMode.LINEAR_LIGHT;
  } else if (key == keyValue('pLit')) {
    return BlendMode.PIN_LIGHT;
  } else if (key == keyValue('hMix')) {
    return BlendMode.HARD_MIX;
  } else if (key == keyValue('diff')) {
    return BlendMode.DIFFERENCE;
  } else if (key == keyValue('smud')) {
    return BlendMode.EXCLUSION;
  } else if (key == keyValue('fsub')) {
    return BlendMode.SUBTRACT;
  } else if (key == keyValue('fdiv')) {
    return BlendMode.DIVIDE;
  } else if (key == keyValue('hue ')) {
    return BlendMode.HUE;
  } else if (key == keyValue('sat ')) {
    return BlendMode.SATURATION;
  } else if (key == keyValue('colr')) {
    return BlendMode.COLOR;
  } else if (key == keyValue('lum ')) {
    return BlendMode.LUMINOSITY;
  }
  return BlendMode.UNKNOWN;
}
