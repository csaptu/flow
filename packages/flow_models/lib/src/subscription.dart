import 'package:equatable/equatable.dart';

/// Subscription plan
class SubscriptionPlan extends Equatable {
  final String id;
  final String name;
  final String tier;
  final double priceMonthly;
  final String currency;
  final List<String> features;
  final bool isPopular;

  const SubscriptionPlan({
    required this.id,
    required this.name,
    required this.tier,
    required this.priceMonthly,
    required this.currency,
    required this.features,
    this.isPopular = false,
  });

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    return SubscriptionPlan(
      id: json['id'] as String,
      name: json['name'] as String,
      tier: json['tier'] as String,
      priceMonthly: (json['price_monthly'] as num).toDouble(),
      currency: json['currency'] as String? ?? 'USD',
      features: (json['features'] as List<dynamic>?)?.cast<String>() ?? [],
      isPopular: json['is_popular'] as bool? ?? false,
    );
  }

  bool get isFree => priceMonthly == 0;

  String get formattedPrice {
    if (isFree) return 'Free';
    return '\$${priceMonthly.toStringAsFixed(2)}/mo';
  }

  @override
  List<Object?> get props => [id, name, tier];
}

/// User's current subscription
class UserSubscription extends Equatable {
  final String tier;
  final String? planId;
  final DateTime? startedAt;
  final DateTime? expiresAt;
  final bool isActive;
  final String? provider;
  final Map<String, dynamic>? usage;

  const UserSubscription({
    required this.tier,
    this.planId,
    this.startedAt,
    this.expiresAt,
    this.isActive = true,
    this.provider,
    this.usage,
  });

  factory UserSubscription.fromJson(Map<String, dynamic> json) {
    return UserSubscription(
      tier: json['tier'] as String? ?? 'free',
      planId: json['plan_id'] as String?,
      startedAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'] as String)
          : null,
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
      isActive: json['is_active'] as bool? ?? true,
      provider: json['provider'] as String?,
      usage: json['usage'] as Map<String, dynamic>?,
    );
  }

  bool get isFree => tier == 'free';
  bool get isLight => tier == 'light';
  bool get isPremium => tier == 'premium';

  @override
  List<Object?> get props => [tier, planId, isActive];
}

/// Checkout response from server
class CheckoutResponse extends Equatable {
  final String orderId;
  final String paddlePriceId;
  final double amount;
  final String currency;
  final String tier;
  final String? returnUrl;

  const CheckoutResponse({
    required this.orderId,
    required this.paddlePriceId,
    required this.amount,
    required this.currency,
    required this.tier,
    this.returnUrl,
  });

  factory CheckoutResponse.fromJson(Map<String, dynamic> json) {
    return CheckoutResponse(
      orderId: json['order_id'] as String,
      paddlePriceId: json['paddle_price_id'] as String,
      amount: (json['amount'] as num).toDouble(),
      currency: json['currency'] as String? ?? 'USD',
      tier: json['tier'] as String,
      returnUrl: json['return_url'] as String?,
    );
  }

  @override
  List<Object?> get props => [orderId, paddlePriceId];
}

/// Order for admin view
class Order extends Equatable {
  final String id;
  final String userId;
  final String? userEmail;
  final String planId;
  final String? planName;
  final String provider;
  final double amount;
  final String currency;
  final String status;
  final DateTime createdAt;
  final DateTime? completedAt;

  const Order({
    required this.id,
    required this.userId,
    this.userEmail,
    required this.planId,
    this.planName,
    required this.provider,
    required this.amount,
    required this.currency,
    required this.status,
    required this.createdAt,
    this.completedAt,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      id: json['id'] as String,
      userId: json['user_id'] as String? ?? '',
      userEmail: json['user_email'] as String?,
      planId: json['plan_id'] as String? ?? '',
      planName: json['plan_name'] as String?,
      provider: json['provider'] as String? ?? 'unknown',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] as String? ?? 'USD',
      status: json['status'] as String? ?? 'unknown',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      completedAt: json['completed_at'] != null
          ? DateTime.tryParse(json['completed_at'] as String)
          : null,
    );
  }

  @override
  List<Object?> get props => [id];
}

/// Admin user view
class AdminUser extends Equatable {
  final String id;
  final String email;
  final String? name;
  final String tier;
  final String? planId;
  final DateTime? subscribedAt;
  final DateTime? expiresAt;
  final int taskCount;
  final DateTime createdAt;

  const AdminUser({
    required this.id,
    required this.email,
    this.name,
    required this.tier,
    this.planId,
    this.subscribedAt,
    this.expiresAt,
    required this.taskCount,
    required this.createdAt,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    return AdminUser(
      id: json['id'] as String,
      email: json['email'] as String? ?? '',
      name: json['name'] as String?,
      tier: json['tier'] as String? ?? 'free',
      planId: json['plan_id'] as String?,
      subscribedAt: json['subscribed_at'] != null
          ? DateTime.tryParse(json['subscribed_at'] as String)
          : null,
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'] as String)
          : null,
      taskCount: (json['task_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [id, email];
}
