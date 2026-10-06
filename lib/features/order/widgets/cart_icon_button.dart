import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:app_quanly_giaiui/core/navigation/app_routes.dart';
import 'package:app_quanly_giaiui/features/order/domain/cart_store.dart';

class CartIconButton extends StatelessWidget {
  const CartIconButton({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CartStore.instance,
      builder: (context, _) {
        final count = CartStore.instance.itemCount;
        return IconButton(
          tooltip: 'Giỏ hàng',
          onPressed: () => context.pushNamed(AppRoutes.cart),
          icon: Badge(
            isLabelVisible: count > 0,
            label: Text('$count'),
            child: Icon(Icons.shopping_cart_outlined, color: color),
          ),
        );
      },
    );
  }
}
