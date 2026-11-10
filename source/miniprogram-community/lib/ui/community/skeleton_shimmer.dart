// 骨架屏 —— **手写,不引入任何包**。
//
// ## ⚠️ 先说它**不是**为了什么:不是"让人觉得更快"
//
// [2026-08-23 复核] 网上关于骨架屏的「感知快 20-30%」「跳出率降 9-20%」
// 「NN/g 2025 指南说 500ms 阈值」全部查无实据:
//   · NN/g 自己的页面(Samhita Tankala, 2024-09-02)**既无百分比也无时间阈值**,
//     只说"它们服务于不同场景"。那些数字是内容农场互相抄出来的。
//   · 唯一一篇同行评议的对照实验(ACM DL 10.1145/3232078.3232086)结论是
//     **"cannot show any significant differences in any of the comparisons"** ——
//     而且**首次进入时用 spinner 的人反而更快找到内容**。
//
// ## 那为什么还要做:**沟通形状**
//
// 换掉的两样东西都不是"慢",是"没说清楚":
//   · _LoadingState 原本是一个 28×28 的转圈,孤零零悬在首屏最大的一块空白里
//     —— 它只说"在忙",没说"要来的是什么"
//   · _CardPlaceholder 原本是静态暗色渐变 + blur_on 图标 —— 它看起来像
//     "这张卡就长这样",而不是"这张卡在加载"
// 骨架给出**版式轮廓**:2 张卡的位置、标题与副标题的行宽。这一条与"更快"无关,
// 也不需要那些编造的数字来支撑。
//
// [D4 2026-08-22 用户签决] 三个候选逐个出局(2026-08-22 实测):
//
//   shimmer            ⛔ issue #64「Extremely high CPU usage causing phone to
//                         overheat」**开了三年未关**,40-60% CPU,多份报告特指
//                         iOS —— 正对本项目的热软肋。
//                         (它"要求 Flutter ≥3.44"那条理由已随 3.47.1 升级作废,
//                          但上面这条与版本无关,仍然成立。)
//   skeleton_loader /
//   skeletons          ⛔ 五年无人维护
//   flutter_animate    ⛔ 是动画库不是骨架屏库,骨头布局照样手写;停更 21 个月
//   skeletonizer       🟡 唯一值得考虑,但:① 需假数据 + 逐个加注解;
//                         ② 每帧 markNeedsPaint() + alwaysNeedsCompositing
//                            ⇒ **整个 feed 每帧全量重绘**;
//                         ③ **热闸插不进去** —— controller 在包内部
//
// 范式直接抄 lib/ui/splash_overlay.dart:39-56 的
// AnimationController(1800ms)..repeat(reverse: true) + AnimatedBuilder。
//
// ⚠️ **必须一并抄它踩过的坑**(splash_overlay.dart:60-70 原话):
//     "Don't spin/pulse behind an invisible overlay — that continuous
//      repaint is what made the sign-in page janky."
// 所以 animate=false 时**显式 stop() 并返回静态图**,不是让它转着但看不见。
//
// ⚠️ 热闸(本项目特有,不可省):一屏跑多个骨架卡是真实的发热面。
// animate 由调用方接 CardLiveGovernor.liveAllowed 传下来 —— 它说不行就一个都不转。

import 'package:flutter/material.dart';

import '../design_system.dart';
import 'masonry_policy.dart';

/// 闪动一轮的时长。与 splash_overlay 的 pulse 同值,观感一致。
const Duration kSkeletonPulsePeriod = Duration(milliseconds: 1800);

/// 灰阶两端。
///
/// [2026-08-23 真机推翻] 这两个值原本是 0xFF1B1B1F / 0xFF26262B —— 我从
/// lib/ui/splash_overlay.dart 抄范式时**把它的底色语境一起抄了过来**:
/// 启动页是深色的,社区页不是。AetherColors 全套是浅色系(bg #FAFAFA、
/// bgElevated #F3F3F2、border #E4E4E4),于是骨架在真机上就是两块纯黑板,
/// 而且两端只差 11/255 ≈ 4%,呼吸也看不出来。用户原话:「为什么没有灰色
/// 状态的闪烁加载,而是完全黑屏」。
///
/// 现在直接绑到令牌上,不再自造色值:
///   · base      = AetherColors.border   #E4E4E4 —— 页面上真实存在的灰
///   · highlight = AetherColors.bg       #FAFAFA —— 页面底色本身
/// [2026-08-24 又一次被真机推翻] 上面那版取 border(#E4E4E4)→bg(#FAFAFA),
/// 两端只差 22/255 ≈ 8.6%,用户原话「灰色,没有任何呼吸闪烁」。设备日志证明
/// 动画**一直在跑**(`live_allowed=true`),看不见纯粹是幅度不够 —— 也就是说
/// 上一版我只修对了"是不是黑的",没修对"看不看得出在动"。
/// 现在两端各往外拉一档,仍然全是既有令牌:
///   · base      = AetherColors.borderStrong  #CCCCCC
///   · highlight = AetherColors.bgElevated    #F3F3F2
/// 两端差 39/255 ≈ 15%,相对亮度差 ~0.30,一整张卡的面积上明确看得见在呼吸。
const Color kSkeletonBase = AetherColors.borderStrong;
const Color kSkeletonHighlight = AetherColors.bgElevated;

// [2026-11-10 用户签决] 封面骨头单独降一档:其余骨头维持上面的 base/highlight,
// 封面用 border(#E4E4E4)→bgCanvas(#FFFFFF),整块面积更浅,呼吸仍然可见。
const Color kSkeletonCoverBase = AetherColors.border;
const Color kSkeletonCoverHighlight = AetherColors.bgCanvas;

/// 一块会轻微呼吸的灰色骨头。
///
/// [animate] 为 false 时**停掉 controller**并画成静态底色 —— 见文件头注释,
/// 不可见时继续重绘正是本仓踩过的那个 jank 来源。
class SkeletonBox extends StatefulWidget {
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final bool animate;

  /// 呼吸两端;默认 kSkeletonBase/kSkeletonHighlight。
  final Color? baseColor;
  final Color? highlightColor;

  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
    this.animate = true,
    this.baseColor,
    this.highlightColor,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: kSkeletonPulsePeriod);
    if (widget.animate) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant SkeletonBox old) {
    super.didUpdateWidget(old);
    if (widget.animate == old.animate) return;
    // 热闸翻转时立刻生效,不等下一轮。
    if (widget.animate) {
      _c.repeat(reverse: true);
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(8);
    final base = widget.baseColor ?? kSkeletonBase;
    final highlight = widget.highlightColor ?? kSkeletonHighlight;
    if (!widget.animate) {
      // 静态:不挂 AnimatedBuilder ⇒ 这棵子树不再每帧重建。
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(color: base, borderRadius: radius),
      );
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: Color.lerp(base, highlight, _c.value),
          borderRadius: radius,
        ),
      ),
    );
  }
}

/// Matches a cover — title line overlaid at its bottom-left — with author and
/// date placeholders below it.
class SkeletonWorkCard extends StatelessWidget {
  final bool animate;

  /// Fill only the media region when used inside WorkCard's loading curtain.
  final bool fill;
  final double coverAspectRatio;
  final BorderRadius? coverBorderRadius;

  const SkeletonWorkCard({
    super.key,
    this.animate = true,
    this.fill = false,
    this.coverAspectRatio = 1,
    this.coverBorderRadius,
  });

  @override
  Widget build(BuildContext context) {
    if (fill) {
      return SkeletonBox(
        animate: animate,
        borderRadius:
            coverBorderRadius ?? BorderRadius.circular(kCommunityCardRadius),
        baseColor: kSkeletonCoverBase,
        highlightColor: kSkeletonCoverHighlight,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(kCommunityCardRadius),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: coverAspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                SkeletonBox(
                  animate: animate,
                  borderRadius: BorderRadius.zero,
                  baseColor: kSkeletonCoverBase,
                  highlightColor: kSkeletonCoverHighlight,
                ),
                // 标题条:压在封面左下角,对应真卡标题叠图的位置。
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: 0.6,
                    child: SkeletonBox(animate: animate, height: 15),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SkeletonBox(
                      animate: animate,
                      width: 20,
                      height: 20,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    const SizedBox(width: 4),
                    Expanded(child: SkeletonBox(animate: animate, height: 13)),
                    const SizedBox(width: 8),
                    SkeletonBox(animate: animate, width: 20, height: 20),
                  ],
                ),
                const SizedBox(height: 4),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: 0.45,
                  child: SkeletonBox(animate: animate, height: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
