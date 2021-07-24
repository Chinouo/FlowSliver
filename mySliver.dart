import 'package:flutter/material.dart';
import 'myrender.dart';
import 'package:flutter/src/widgets/sliver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/src/widgets/framework.dart';

/*
usage: 

  FlowSliver.builder(
            delegate: _delegate(),
            gridDelegate:
                FlowSliverDelegateWithFixedCrossAxisCount(crossItemCount: 2)
    ),
 
  FlowSliver.count(
            children:[
              Container(height: 200,color: Colors.blue),
              Container(height: 100,color: Colors.red),
              Container(height: 150,color: Colors.green),
              Container(height: 250,color: Colors.yellow)
            ]
            gridDelegate:
                FlowSliverDelegateWithFixedCrossAxisCount(crossItemCount: 2)
    ),
 */

class FlowSliverChildBuilderDelegate extends SliverChildDelegate {
  FlowSliverChildBuilderDelegate(this.builder, {this.childCount});
  final NullableIndexedWidgetBuilder builder;

  int? childCount;
  @override
  Widget? build(BuildContext context, int index) {
    assert(builder != null);
    if (index < 0 || (childCount != null && index >= childCount!)) return null;
    Widget? child;

    child = builder(context, index);

    if (child == null) {
      return null;
    }
  }

  @override
  bool shouldRebuild(covariant FlowSliverChildBuilderDelegate oldDelegate) {
    return oldDelegate.childCount == this.childCount;
  }
}

//Widget  用在CustomScrollView的sliver属性
class FlowSliver extends SliverMultiBoxAdaptorWidget {
  FlowSliver(
      {Key? key,
      required SliverChildDelegate delegate,
      required this.gridDelegate})
      : super(key: key, delegate: delegate) {
    print("i am rebuild!");
  }

  FlowSliver.builder(
      {Key? key,
      required SliverChildDelegate delegate,
      required this.gridDelegate})
      : super(key: key, delegate: delegate) {}

  FlowSliver.count({
    Key? key,
    double mainAxisSpacing = 0.0,
    double crossAxisSpacing = 0.0,
    List<Widget> children = const <Widget>[],
  })  : gridDelegate =
            FlowSliverDelegateWithFixedCrossAxisCount(crossItemCount: 2),
        super(key: key, delegate: SliverChildListDelegate(children));

  final FlowSliverDelegate gridDelegate;

  @override
  RenderFlowSliver createRenderObject(BuildContext context) {
    final SliverMultiBoxAdaptorElement element =
        context as SliverMultiBoxAdaptorElement;
    return RenderFlowSliver(childManager: element, gridDelegate: gridDelegate);
  }

  @override
  void updateRenderObject(BuildContext context, RenderFlowSliver renderObject) {
    renderObject.gridDelegate = gridDelegate;
  }
}
