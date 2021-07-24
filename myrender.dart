import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/*
 add that to  SliverMultiBoxAdaptorElement which is in sliver.dart 

//我修改的
  void mycreateChild(int index,
      {required RenderBox? after, required int beforeIndex}) {
    assert(_currentlyUpdatingChildIndex == null);
    owner!.buildScope(this, () {
      final bool insertFirst = after == null;
      assert(insertFirst || _childElements[beforeIndex] != null);
      _currentBeforeChild = insertFirst
          ? null
          : (_childElements[beforeIndex]!.renderObject as RenderBox?);
      Element? newChild;
      try {
        _currentlyUpdatingChildIndex = index;
        newChild = updateChild(_childElements[index], _build(index), index);
      } finally {
        _currentlyUpdatingChildIndex = null;
      }
      if (newChild != null) {
        _childElements[index] = newChild;
      } else {
        _childElements.remove(index);
      }
    });
  }
*/

//所有没被回收卡片的布局管理类
class FlowSliverLayout {
  FlowSliverLayout(this.crossAxisExtent);
  final crossAxisExtent;
}

abstract class FlowSliverDelegate {
  const FlowSliverDelegate();

  FlowSliverLayout getLayout(SliverConstraints constraints);

  bool shouldRelayout(covariant FlowSliverDelegate oldDelegate);
}

class FlowSliverDelegateWithFixedCrossAxisCount extends FlowSliverDelegate {
  const FlowSliverDelegateWithFixedCrossAxisCount({
    required this.crossItemCount,
  });

  final int crossItemCount;

  @override
  FlowSliverLayout getLayout(SliverConstraints constraints) {
    final crossAxisExtent = constraints.crossAxisExtent;
    return FlowSliverLayout(crossAxisExtent);
  }

  @override
  bool shouldRelayout(
      covariant FlowSliverDelegateWithFixedCrossAxisCount oldDelegate) {
    return oldDelegate.crossItemCount != crossItemCount;
  }
}

//如果使用随机大小的container并且使用hot restart 记录已布局的元素会出现error
//原因在于随机大小元素每次的长度不一  而代码并没有针对这个做处理
//官方的listview用随机长度container，也有这种情况，因为每次都要去想element要widget的build 每次都不一样 widget is imutable!!
//控制管理children得渲染
//已知bug 当滑动过快  creatElement会出现错误 说是访问下表过界了  其他情况下暂无发现bug
class RenderFlowSliver extends RenderSliverMultiBoxAdaptor {
  RenderFlowSliver(
      {required RenderSliverBoxChildManager childManager,
      required FlowSliverDelegate gridDelegate})
      : _gridDelegate = gridDelegate,
        super(childManager: childManager);

//设置更新
  FlowSliverDelegate _gridDelegate;
  FlowSliverDelegate get gridDelegate => _gridDelegate;
  set gridDelegate(FlowSliverDelegate value) {
    if (_gridDelegate == value) return;
    if (value.runtimeType != _gridDelegate.runtimeType ||
        value.shouldRelayout(_gridDelegate)) markNeedsLayout();
    _gridDelegate = value;
  }

  @override
  double childCrossAxisPosition(RenderBox child) {
    final parentData = child.parentData as FlowSliverParentData;
    return parentData.crossAxisPosition;
  }

  //记录已布局的元素的下标信息 即第几个元素在第几个元素上方
  void layoutChildUpdate(List tempLayoutChildIndex, int crossItemCount) {
    // print(tempLayoutChildIndex);
    for (int i = 0; i < crossItemCount; ++i) {
      if (tempLayoutChildIndex[i][0] > layoutedChildren[i].last) {
        layoutedChildren[i].addAll(tempLayoutChildIndex[i]);
        continue;
      }

      int newIndex = layoutedChildren[i].indexOf(tempLayoutChildIndex[i].first);
      layoutedChildren[i] = layoutedChildren[i].sublist(0, newIndex);
      layoutedChildren[i].addAll(tempLayoutChildIndex[i]);
    }
  }

  //返回最上方卡片的childScrollOffset
  double getLeadingOffset() {
    //给geometry用的 最顶部的卡片
    assert(leadingChildContainer[0] != null);
    double offset = childScrollOffset(leadingChildContainer[0]!)!;
    for (int i = 1;
        i < leadingChildContainer.length && leadingChildContainer[i] != null;
        ++i) {
      if (offset > childScrollOffset(leadingChildContainer[i]!)!)
        offset = childScrollOffset(leadingChildContainer[i]!)!;
    }
    return offset;
  }

//返回最下方卡片最长的一个 供geometry使用
  double getTrailingOffset() {
    assert(trailingChildContainer[0] != null);
    double offset = childScrollOffset(trailingChildContainer[0]!)! +
        paintExtentOf(trailingChildContainer[0]!);
    for (int i = 1;
        i < trailingChildContainer.length && trailingChildContainer[i] != null;
        ++i) {
      if (offset <
          childScrollOffset(trailingChildContainer[i]!)! +
              paintExtentOf(trailingChildContainer[i]!))
        offset = childScrollOffset(trailingChildContainer[i]!)! +
            paintExtentOf(trailingChildContainer[i]!);
    }
    return offset;
  }

//返回trailing中Index最大的那位
  RenderBox getTrailingMaxIndexChild() {
    RenderBox child = trailingChildContainer[0]!;
    var index = indexOf(child);
    for (int i = 1; i < trailingChildContainer.length; i++) {
      assert(trailingChildContainer[i] != null);
      if (indexOf(trailingChildContainer[i]!) > index) {
        index = indexOf(trailingChildContainer[i]!);
        child = trailingChildContainer[i]!;
      }
    }
    return child;
  }

//返回下方卡片中 最短的那个卡片的renderBox
  RenderBox getTrailingChild() {
    RenderBox child = trailingChildContainer[0]!;
    var endOffset = paintExtentOf(child) + childScrollOffset(child)!;
    for (int i = 1; i < trailingChildContainer.length; i++) {
      if (paintExtentOf(trailingChildContainer[i]!) +
              childScrollOffset(trailingChildContainer[i]!)! <
          endOffset) {
        endOffset = paintExtentOf(trailingChildContainer[i]!) +
            childScrollOffset(trailingChildContainer[i]!)!;
        child = trailingChildContainer[i]!;
      }
    }
    return child;
  }

//回收底部元素  必须放在输出布局后
  void collectTrailing(int gcCount) {
    collectGarbage(0, gcCount);
  }

  //向下更新第i列的leading i从0开始
  void updateLeadingContainer(
      int i, RenderBox leading, double crossItemExtent) {
    RenderBox nextleading = childAfter(leading)!;
    final needLayoutcrossAxisPosition = i * crossItemExtent;

    var data = nextleading.parentData as FlowSliverParentData;
    while (data.crossAxisPosition != needLayoutcrossAxisPosition) {
      nextleading = childAfter(nextleading)!;
      data = nextleading.parentData as FlowSliverParentData;
    }

    leadingChildContainer[i] = nextleading;
  }

//回收顶部元素
  void collectLeading(double crossItemExtent, double scrollOffset) {
    for (int i = 0;
        i <
            (gridDelegate as FlowSliverDelegateWithFixedCrossAxisCount)
                .crossItemCount;
        ++i) {
      var child = leadingChildContainer[i]!;

      while (paintExtentOf(child) + childScrollOffset(child)! < scrollOffset) {
        //print(constraints.scrollOffset + constraints.cacheOrigin);
        // print(paintExtentOf(child) + childScrollOffset(child)!);
        updateLeadingContainer(i, child, crossItemExtent);

        invokeLayoutCallback((constraints) {
          childManager.removeChild(child);
        });
        child = leadingChildContainer[i]!;
      }
    }
  }

//找到插入的那个after元素
  RenderBox? getChildBeforeIndex(int index) {
    RenderBox child = firstChild!;
    while (indexOf(child) < index) {
      child = childAfter(child)!;
    }
    return childBefore(child);
  }

//视窗上移时添加元素
  void insertLeadingIfNeed(BoxConstraints childConstraints, double scrollOffset,
      double childMaxExtent) {
    for (int i = 0;
        i <
            (gridDelegate as FlowSliverDelegateWithFixedCrossAxisCount)
                .crossItemCount;
        ++i) {
      var child = leadingChildContainer[i]!;

      while (childScrollOffset(child)! > scrollOffset) {
        //print(constraints.scrollOffset + constraints.cacheOrigin);
        // print(paintExtentOf(child) + childScrollOffset(child)!);

        var index = layoutedChildren[i][layoutedChildren[i]
                .indexWhere((element) => element == indexOf(child)) -
            1];

        var afterchild = getChildBeforeIndex(index);
        var newchild;
        //print(index);
        //找到的是第一个元素
        if (afterchild == null) {
          //这个地方要遵循 sliver的 createChild方法

          invokeLayoutCallback((constraints) {
            childManager.createChild(index, after: afterchild);
          });
          newchild = firstChild;
        } else {
          invokeLayoutCallback((constraints) {
            (childManager as SliverMultiBoxAdaptorElement).mycreateChild(index,
                after: afterchild, beforeIndex: indexOf(afterchild));
          });
          newchild = childAfter(afterchild);
        }

        newchild!.layout(childConstraints, parentUsesSize: true);
        var data = newchild.parentData as FlowSliverParentData;
        data.crossAxisPosition = i * childMaxExtent;

        data.layoutOffset = childScrollOffset(child)! - paintExtentOf(newchild);

        leadingChildContainer[i] = newchild;
        child = newchild;
      }
    }
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! FlowSliverParentData)
      child.parentData = FlowSliverParentData();
  }

  //为 最上方两张卡片的RenderBox
  List<RenderBox?> leadingChildContainer = [];
  //为 最下方两张卡片的RenderBox
  List<RenderBox?> trailingChildContainer = [];
  //储存已经布局的元素信息
  List layoutedChildren = [];

  @override
  void performLayout() {
    final SliverConstraints constraints = this.constraints;
    childManager.didStartLayout();
    childManager.setDidUnderflow(false);

    final double scrollOffset =
        constraints.scrollOffset + constraints.cacheOrigin;

    assert(scrollOffset >= 0.0);
    final double remainingExtent = constraints.remainingCacheExtent;
    assert(remainingExtent >= 0.0);
    final double targetEndScrollOffset = scrollOffset + remainingExtent;
    final delegate = gridDelegate as FlowSliverDelegateWithFixedCrossAxisCount;
    final childMaxExtent =
        constraints.crossAxisExtent / delegate.crossItemCount;
    final BoxConstraints childConstraints =
        BoxConstraints(minWidth: childMaxExtent, maxHeight: 600);

    //首次布局
    if (firstChild == null) {
      //看看是否有元素可以初始化
      if (!addInitialChild()) {
        // There are no children.
        geometry = SliverGeometry.zero;
        childManager.didFinishLayout();
        return;
      }
      //此处firstChild 已经存在 且一定等于lastChild
      for (int i = 0; i < delegate.crossItemCount; ++i) {
        leadingChildContainer.add(null);
        trailingChildContainer.add(null);
        //创建表来存放已经储存的元素信息
        layoutedChildren.add(<int>[]);
      }

      //下述处理元素还没添加满一整行的情况
      assert(firstChild != null);
      firstChild!.layout(childConstraints, parentUsesSize: true);

      var childData = firstChild!.parentData as FlowSliverParentData;
      childData.crossAxisPosition = 0;
      childData.layoutOffset = 0;

      leadingChildContainer[0] = trailingChildContainer[0] = firstChild;
      layoutedChildren[0].add(0);
      RenderBox? child = firstChild;
      //添加到元素充满一整行为止 如果加不满就跳出
      while (leadingChildContainer.last == null) {
        child = insertAndLayoutChild(childConstraints,
            after: child, parentUsesSize: true);
        //we are run out of child
        if (child == null) {
          double frontOffset = getLeadingOffset();

          double endOffset = getTrailingOffset();
          //输出布局信息
          final double estimatedMaxScrollOffset =
              childManager.estimateMaxScrollOffset(
            constraints,
            firstIndex: indexOf(firstChild!),
            lastIndex: indexOf(lastChild!),
            leadingScrollOffset: frontOffset,
            trailingScrollOffset: endOffset,
          );

          final double paintExtent = calculatePaintOffset(
            constraints,
            from: frontOffset,
            to: endOffset,
          );

          final double cacheExtent = calculateCacheOffset(
            constraints,
            from: frontOffset,
            to: endOffset,
          );
          final double targetEndScrollOffsetForPaint =
              constraints.scrollOffset + constraints.remainingPaintExtent;
          geometry = SliverGeometry(
              scrollExtent: estimatedMaxScrollOffset,
              paintExtent: paintExtent,
              cacheExtent: cacheExtent,
              maxPaintExtent: endOffset,
              hasVisualOverflow: endOffset > targetEndScrollOffsetForPaint ||
                  constraints.scrollOffset > 0.0);
          //
          geometry = SliverGeometry(
              scrollExtent: estimatedMaxScrollOffset,
              paintExtent: paintExtent,
              cacheExtent: cacheExtent,
              maxPaintExtent: endOffset,
              hasVisualOverflow: endOffset > targetEndScrollOffsetForPaint ||
                  constraints.scrollOffset > 0.0);
          childManager.didFinishLayout();
          return;
        }
        childData = child.parentData as FlowSliverParentData;
        childData.crossAxisPosition = indexOf(child) * childMaxExtent;
        childData.layoutOffset = 0;
        leadingChildContainer[indexOf(child)] = child;
        trailingChildContainer[indexOf(child)] = child;
        layoutedChildren[indexOf(child)].add(indexOf(child));
      }
      //上述处理元素还没添加满一整行的情况
    }
    var child;
    //将顶部所有元素layout
    for (int i = 0; i < delegate.crossItemCount; ++i) {
      leadingChildContainer[i]!.layout(childConstraints, parentUsesSize: true);
    }

    //视窗上滑时 添加顶部元素
    insertLeadingIfNeed(childConstraints, scrollOffset, childMaxExtent);
    //临时表 防止乱序
    List tempLayoutChildIndex = [];
    for (int i = 0; i < delegate.crossItemCount; ++i) {
      trailingChildContainer[i] = leadingChildContainer[i];
      tempLayoutChildIndex.add(<int>[]);
      tempLayoutChildIndex[i].add(indexOf(leadingChildContainer[i]!));
    }

    //这边可以优化
    //记下各个纵轴的偏移量 供计算方便
    List<double> crossOffsetCollection = [0.0];
    for (int i = 1; i < delegate.crossItemCount; ++i) {
      crossOffsetCollection.add(childMaxExtent * i);
    }

    //获得顶部最短卡片
    var trailchild = getTrailingChild();
    while (childScrollOffset(trailchild)! < targetEndScrollOffset) {
      //下个卡片
      child = childAfter(getTrailingMaxIndexChild());
      if (child == null) {
        //卡片不够向下 去找manger要 加在lastchild
        child = insertAndLayoutChild(childConstraints,
            after: lastChild, parentUsesSize: true);
        if (child == null) {
          //we are run out of children
          break;
        }
      }

      // createNewOne And layout it
      // child.layout(childConstraints, parentUsesSize: true);
      var data = child.parentData as FlowSliverParentData;
      var ceildata = trailchild.parentData as FlowSliverParentData;
      data.crossAxisPosition = ceildata.crossAxisPosition;
      data.layoutOffset = paintExtentOf(trailchild) + ceildata.layoutOffset!;
      int i = 0;
      for (; i < delegate.crossItemCount; i++) {
        if (crossOffsetCollection[i] == data.crossAxisPosition) {
          trailingChildContainer[i] = child;
          break;
        }
      }
      child.layout(childConstraints, parentUsesSize: true);
      tempLayoutChildIndex[i].add(indexOf(child));
      trailchild = getTrailingChild();
    }

    //
    layoutChildUpdate(tempLayoutChildIndex, delegate.crossItemCount);

    //  print(layoutedChildren);
//输出布局
    double frontOffset = getLeadingOffset();

    double endOffset = getTrailingOffset();

    final double estimatedMaxScrollOffset =
        childManager.estimateMaxScrollOffset(
      constraints,
      firstIndex: indexOf(firstChild!),
      lastIndex: indexOf(lastChild!),
      leadingScrollOffset: frontOffset,
      trailingScrollOffset: endOffset,
    );

    final double paintExtent = calculatePaintOffset(
      constraints,
      from: frontOffset,
      to: endOffset,
    );

    final double cacheExtent = calculateCacheOffset(
      constraints,
      from: frontOffset,
      to: endOffset,
    );
    final double targetEndScrollOffsetForPaint =
        constraints.scrollOffset + constraints.remainingPaintExtent;
    geometry = SliverGeometry(
        scrollExtent: estimatedMaxScrollOffset,
        paintExtent: paintExtent,
        cacheExtent: cacheExtent,
        maxPaintExtent: endOffset,
        hasVisualOverflow: endOffset > targetEndScrollOffsetForPaint ||
            constraints.scrollOffset > 0.0);

//gc 必须放在最后面
    int trailgc = 0;
    if (child != null) {
      trailgc = indexOf(lastChild!) - indexOf(child);
    }

    collectTrailing(trailgc);
    collectLeading(childMaxExtent, scrollOffset);

    childManager.didFinishLayout();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (firstChild == null) return;
    // offset is to the top-left corner, regardless of our axis direction.
    // originOffset gives us the delta from the real origin to the origin in the axis direction.
    final Offset mainAxisUnit, crossAxisUnit, originOffset;
    final bool addExtent;
    switch (applyGrowthDirectionToAxisDirection(
        constraints.axisDirection, constraints.growthDirection)) {
      case AxisDirection.up:
        mainAxisUnit = const Offset(0.0, -1.0);
        crossAxisUnit = const Offset(1.0, 0.0);
        originOffset = offset + Offset(0.0, geometry!.paintExtent);
        addExtent = true;
        break;
      case AxisDirection.right:
        mainAxisUnit = const Offset(1.0, 0.0);
        crossAxisUnit = const Offset(0.0, 1.0);
        originOffset = offset;
        addExtent = false;
        break;
      case AxisDirection.down:
        mainAxisUnit = const Offset(0.0, 1.0);
        crossAxisUnit = const Offset(1.0, 0.0);
        originOffset = offset;
        addExtent = false;
        break;
      case AxisDirection.left:
        mainAxisUnit = const Offset(-1.0, 0.0);
        crossAxisUnit = const Offset(0.0, 1.0);
        originOffset = offset + Offset(geometry!.paintExtent, 0.0);
        addExtent = true;
        break;
    }
    assert(mainAxisUnit != null);
    assert(addExtent != null);
    RenderBox? child = firstChild;
    while (child != null) {
      final double mainAxisDelta = childMainAxisPosition(child);
      final double crossAxisDelta =
          (child.parentData as FlowSliverParentData).crossAxisPosition;
      Offset childOffset = Offset(
        originOffset.dx +
            mainAxisUnit.dx * mainAxisDelta +
            crossAxisUnit.dx * crossAxisDelta,
        originOffset.dy +
            mainAxisUnit.dy * mainAxisDelta +
            crossAxisUnit.dy * crossAxisDelta,
      );
      if (addExtent) childOffset += mainAxisUnit * paintExtentOf(child);

      // If the child's visible interval (mainAxisDelta, mainAxisDelta + paintExtentOf(child))
      // does not intersect the paint extent interval (0, constraints.remainingPaintExtent), it's hidden.
      if (mainAxisDelta < constraints.remainingPaintExtent &&
          mainAxisDelta + paintExtentOf(child) > 0)
        context.paintChild(child, childOffset);

      child = childAfter(child);
    }
  }
}

class FlowSliverParentData extends SliverMultiBoxAdaptorParentData {
  //主轴偏移量
  double crossAxisPosition = 0.0;
}

class LayoutedChildData {
  const LayoutedChildData(
      this._index, this.crossAxisOffset, this.scrollOffset, this.paintExtent);
  final int _index;
  final double scrollOffset;
  final double crossAxisOffset;
  final double paintExtent;

  get index => _index;
  @override
  String toString() {
    return "index:$index scrollOffset:$scrollOffset crossAxisOffset:$crossAxisOffset paintExtent:$paintExtent";
  }
}
