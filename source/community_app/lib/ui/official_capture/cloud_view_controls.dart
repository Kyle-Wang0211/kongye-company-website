import 'package:flutter/foundation.dart';

typedef CloudViewCamera = ({
  double yaw,
  double pitch,

  /// 屏幕滚转。[2026-07-29 用户签决"框不动、点云转"] 旋转滑轨绕任意世界轴
  /// 转相机,分解出来一般带滚转,故提升为一等相机分量。
  double roll,
  double zoom,
  double panX,
  double panY,
  double pivotX,
  double pivotY,
  double pivotZ,
});

class CloudViewController extends ChangeNotifier {
  CloudViewCamera? _target;
  bool _reframe = false;

  void moveTo(CloudViewCamera c) {
    _target = c;
    notifyListeners();
  }

  CloudViewCamera? takeTarget() {
    final t = _target;
    _target = null;
    return t;
  }

  /// 请求回到默认取景("回到初始点云大小")。
  void requestReframe() {
    _reframe = true;
    notifyListeners();
  }

  bool takeReframe() {
    final r = _reframe;
    _reframe = false;
    return r;
  }

  /// 视角吸附动画期间,选区矩形按**目标**姿态画(不跟中间帧)。
  ///
  /// [2026-08-09 用户实机指认] "切换视角,框不要每次突然变大再缩小,直接变成
  /// 对应角度的大小" —— 立方体在中间角度的投影支撑矩形必然鼓一下,锁定目标
  /// 姿态后矩形直达终态,点云照常转。
  (double yaw, double pitch, double roll)? rectPoseOverride;

  void setRectPoseOverride((double, double, double)? pose) {
    rectPoseOverride = pose;
    notifyListeners();
  }

  bool _browsePose = false;

  /// 请求把**朝向**恢复成浏览态的斜上 45°(退出编辑用)。
  ///
  /// [2026-08-08 用户签决] "如果用户在编辑页面什么都没做,直接点取消了,那就恢复
  /// 到斜上 45 度。如果用户编辑了点云大小,点击完成后,就保留在当前视角。" ——
  /// 所以这个请求只由"取消"发出,"完成"什么都不做。
  ///
  /// 只动朝向,不动 zoom/pan:用户说的是"恢复到斜上 45 度"(角度),把缩放一起
  /// 重置会顺手丢掉他在编辑期捏的远近。要连取景一起回,用 [requestReframe]。
  void requestBrowsePose() {
    _browsePose = true;
    notifyListeners();
  }

  bool takeBrowsePose() {
    final r = _browsePose;
    _browsePose = false;
    return r;
  }

  /// [175] True while a view with `flatIsStandIn` shows nothing because its dense cloud is not
  /// on screen yet; the page draws its wait label from this (in the same place as its loading
  /// label, so the hand-over does not jump). Starts true: the page's first frame with the view
  /// already waits, before the view could report. Meaningless while `flatIsStandIn` is false.
  final ValueNotifier<bool> waitingForDense = ValueNotifier<bool>(true);

  @override
  void dispose() {
    waitingForDense.dispose();
    super.dispose();
  }
}
