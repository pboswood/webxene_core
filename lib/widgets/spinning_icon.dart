import 'package:flutter/material.dart';

// Icon widget that spins at speed controlled by the controller. To use this, the parent widget
// must mixin SingleTickerProviderStateMixin, and pass in an AnimationController with
// Duration+Vsync parameters.
class SpinningIcon extends AnimatedWidget {
	final AnimationController controller;
	final IconData? iconData;
	final double? iconSize;
	final Color? iconColor;
	const SpinningIcon({Key? key, required this.controller, required this.iconData, this.iconSize, this.iconColor }) :
		super(key: key, listenable: controller);

	@override Widget build(BuildContext context) {
		final Animation<double> _animation = CurvedAnimation(
			parent: controller,
			curve: Curves.linear,
		);
		return RotationTransition(
			alignment: Alignment.center,
			turns: _animation,
			child: Icon(iconData, size: iconSize, color: iconColor,),
		);
	}
}