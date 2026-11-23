class Customer {
  final int? id;
  final String customerType;
  final String name;
  final String phone;
  final String address;
  final String device;
  final String symptom;
  final String amount;
  final String materialCost;
  final String paymentStatus;
  final String memo;
  final String visitDate;

  Customer({
    this.id,
    this.customerType = '개인',
    required this.name,
    required this.phone,
    required this.address,
    required this.device,
    required this.symptom,
    required this.amount,
    this.materialCost = '0',
    required this.paymentStatus,
    required this.memo,
    required this.visitDate,
  });

  int get amountInt => int.tryParse(amount.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  int get materialCostInt => int.tryParse(materialCost.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  int get netProfit => amountInt - materialCostInt;
  int get estimatedVat => (amountInt / 11).round();
  int get estimatedCardFee => paymentStatus == '카드결제' ? (amountInt * 0.015).round() : 0;

  int get estimatedIncomeTax {
    final taxable = netProfit - estimatedVat - estimatedCardFee;
    return taxable > 0 ? (taxable * 0.15).round() : 0;
  }

  int get afterTaxNetProfit => netProfit - estimatedVat - estimatedCardFee - estimatedIncomeTax;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customer_type': customerType,
      'name': name,
      'phone': phone,
      'address': address,
      'device': device,
      'symptom': symptom,
      'amount': amount,
      'material_cost': materialCost,
      'payment_status': paymentStatus,
      'memo': memo,
      'visit_date': visitDate,
    };
  }

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id'],
      customerType: map['customer_type'] ?? '개인',
      name: map['name'] ?? '',
      phone: map['phone'] ?? '',
      address: map['address'] ?? '',
      device: map['device'] ?? '',
      symptom: map['symptom'] ?? '',
      amount: map['amount'] ?? '',
      materialCost: map['material_cost'] ?? '0',
      paymentStatus: map['payment_status'] ?? '',
      memo: map['memo'] ?? '',
      visitDate: map['visit_date'] ?? '',
    );
  }
}