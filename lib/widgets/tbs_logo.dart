import 'package:flutter/material.dart';

class TbsLogo extends StatelessWidget {
  const TbsLogo({super.key, this.width = 220});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/tbs.jpg',
      width: width,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) {
        return const Text(
          'TBS',
          style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
        );
      },
    );
  }
}
