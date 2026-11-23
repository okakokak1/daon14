import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../db/database_helper.dart';
import '../models/customer.dart';

class KoreanPhoneFormatter extends TextInputFormatter {
  static String formatNumber(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';

    if (digits.startsWith('02')) {
      if (digits.length <= 2) return digits;
      if (digits.length <= 5) return '${digits.substring(0, 2)}-${digits.substring(2)}';
      if (digits.length <= 9) {
        return '${digits.substring(0, 2)}-${digits.substring(2, 5)}-${digits.substring(5)}';
      }
      final end = digits.length > 10 ? 10 : digits.length;
      return '${digits.substring(0, 2)}-${digits.substring(2, 6)}-${digits.substring(6, end)}';
    } else if (digits.startsWith('15') || digits.startsWith('16') || digits.startsWith('18')) {
      if (digits.length <= 4) return digits;
      final end = digits.length > 8 ? 8 : digits.length;
      return '${digits.substring(0, 4)}-${digits.substring(4, end)}';
    } else {
      if (digits.length <= 3) return digits;
      if (digits.length <= 7) return '${digits.substring(0, 3)}-${digits.substring(3)}';
      if (digits.length <= 10) {
        return '${digits.substring(0, 3)}-${digits.substring(3, 6)}-${digits.substring(6)}';
      }
      final end = digits.length > 11 ? 11 : digits.length;
      return '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7, end)}';
    }
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final formatted = formatNumber(newValue.text);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _overlayChannel = MethodChannel('com.daonsystem.daon_crm/overlay');
  final _numFormat = NumberFormat('#,###');

  int _tabIndex = 0;
  List<Customer> _customers = [];
  Customer? _selectedCustomer;
  final TextEditingController _searchController = TextEditingController();
  String _selectedMonth = DateFormat('yyyy-MM').format(DateTime.now());

  String _sortBy = 'date_desc';
  String _typeFilter = '전체';
  bool _onlyUnpaid = false;

  bool _hasOverlayPerm = false;
  bool _hasPhonePerm = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshCustomers();
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    final pOverlay = await Permission.systemAlertWindow.isGranted;
    final pPhone = await Permission.phone.isGranted;
    if (pPhone) {
      try {
        await _overlayChannel.invokeMethod('startMonitorService');
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _hasOverlayPerm = pOverlay;
        _hasPhonePerm = pPhone;
      });
    }
  }

  void _showSamsungRestrictedGuide() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('📞 원 UI 9 팝업 필수 설정', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('갤럭시 원 UI 9에서는 아래 3가지를 켜야 전화 수신 팝업이 뜹니다:\n', style: TextStyle(fontSize: 13)),
              Text('1️⃣ 제한된 설정 허용 (통화기록 잠금해제)', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFD32F2F))),
              Text('   [앱 설정 열기] → 우측 상단 점3개(⋮) → [제한된 설정 허용] → [권한]에서 전화·통화 기록 허용\n', style: TextStyle(fontSize: 12)),
              Text('2️⃣ 다른 앱 위에 표시 & 전체 화면 알림 허용', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFD32F2F))),
              Text('   같은 화면에서 [다른 앱 위에 표시] 켜기 + [알림] → 전체 화면 알림 허용\n', style: TextStyle(fontSize: 12)),
              Text('3️⃣ 기본 발신자 ID 앱 지정', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFD32F2F))),
              Text('   폰 설정 → 애플리케이션 → 기본 앱 선택 → 발신자 ID 및 스팸 앱 → 다온시스템 CRM 선택', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫기')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD32F2F), foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await _overlayChannel.invokeMethod('openAppSettings');
            },
            child: const Text('앱 설정 바로 열기'),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshCustomers([String query = '']) async {
    final list = await DatabaseHelper.instance.getCustomers(query);
    if (!mounted) return;
    setState(() {
      _customers = list;
      if (_selectedCustomer != null) {
        final updated = list.where((e) => e.id == _selectedCustomer!.id).toList();
        _selectedCustomer = updated.isNotEmpty ? updated.first : null;
      }
    });
  }

  List<Customer> get _filteredAndSortedCustomers {
    Iterable<Customer> items = _customers;

    if (_onlyUnpaid) {
      items = items.where((c) => c.paymentStatus == '미수금');
    }
    if (_typeFilter != '전체') {
      items = items.where((c) => c.customerType == _typeFilter);
    }

    final list = items.toList();
    switch (_sortBy) {
      case 'date_asc':
        list.sort((a, b) => a.visitDate.compareTo(b.visitDate));
        break;
      case 'amount_desc':
        list.sort((a, b) => b.amountInt.compareTo(a.amountInt));
        break;
      case 'amount_asc':
        list.sort((a, b) => a.amountInt.compareTo(b.amountInt));
        break;
      case 'date_desc':
      default:
        list.sort((a, b) {
          final cmp = b.visitDate.compareTo(a.visitDate);
          return cmp != 0 ? cmp : (b.id ?? 0).compareTo(a.id ?? 0);
        });
        break;
    }
    return list;
  }

  String _extractPureKoreanAddress(String rawText) {
    final lines = rawText.split(RegExp(r'[\r\n/]+'));
    final cityStartRegex = RegExp(
      r'((?:서울|경기|인천|강원|충북|충남|대전|세종|전북|전남|광주|경북|경남|대구|울산|부산|제주)(?:특별시|광역시|특별자치시|도|특별자치도)?\s+)?'
      r'([가-힣]{1,6}(?:시|군|구)\s+[가-힣0-9\s\-\(\),\.]+)',
    );

    String candidate = '';
    for (final line in lines) {
      final cleanedLine = line.replaceAll(RegExp(r'^(?:주소|방문지|위치|장소)\s*[:：]\s*'), '').trim();
      final m = cityStartRegex.firstMatch(cleanedLine);
      if (m != null && m.group(0)!.trim().length >= 6) {
        candidate = m.group(0)!;
        break;
      }
    }

    if (candidate.isEmpty) {
      final fallback = cityStartRegex.firstMatch(rawText);
      if (fallback != null) candidate = fallback.group(0)!;
    }
    if (candidate.isEmpty) return '';

    candidate = candidate
        .replaceAll(RegExp(r'01[016789]-?\d{3,4}-?\d{4}.*$'), '')
        .replaceAll(RegExp(r'0\d{1,2}-?\d{3,4}-?\d{4}.*$'), '')
        .replaceAll(RegExp(r'(?:증상|연락처|전화|기종|문의|접수|출장|노트북|데스크톱|컴퓨터|외장하드|서버|본체)\s*[:：]?.*$'), '')
        .replaceAll(RegExp(r'(?:입니다|이에요|예요|인데|에서|으로\s*오세요|방문\s*부탁).*$'), '')
        .replaceAll(RegExp(r'[,.\s]+$'), '')
        .trim();

    return candidate;
  }

  Future<void> _sendSmsToCustomer(Customer c) async {
    final cleanPhone = c.phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleanPhone.isEmpty) return;
    final smsUri = Uri.parse('smsto:$cleanPhone');
    if (await canLaunchUrl(smsUri)) {
      await launchUrl(smsUri, mode: LaunchMode.externalApplication);
    } else {
      await launchUrl(Uri.parse('sms:$cleanPhone'), mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openNaverMapApp(String address) async {
    if (address.trim().isEmpty) return;
    final cleanAddr = address.trim();
    final encodedAddr = Uri.encodeComponent(cleanAddr);

    final searchAppUri = Uri.parse('nmap://search?query=$encodedAddr&appname=com.daonsystem.daon_crm');
    final webUri = Uri.parse('https://m.map.naver.com/search2/search.naver?query=$encodedAddr');

    if (await canLaunchUrl(searchAppUri)) {
      await launchUrl(searchAppUri, mode: LaunchMode.externalApplication);
    } else {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
  }

  Future<String> _buildCsvText() async {
    final allCustomers = await DatabaseHelper.instance.getCustomers();
    if (allCustomers.isEmpty) return '';

    final List<List<dynamic>> rows = [
      ['방문일자', '구분', '고객명/상호', '전화번호', '방문지역/주소', '기종', '고장증상/작업내역', '총청구금액', '자재비', '예상부가세', '카드수수료', '예상소득세', '세후순수익', '결제상태', '메모']
    ];

    for (final c in allCustomers) {
      rows.add([
        c.visitDate,
        c.customerType,
        c.name,
        c.phone,
        c.address,
        c.device,
        c.symptom,
        c.amountInt,
        c.materialCostInt,
        c.estimatedVat,
        c.estimatedCardFee,
        c.estimatedIncomeTax,
        c.afterTaxNetProfit,
        c.paymentStatus,
        c.memo,
      ]);
    }
    return const ListToCsvConverter().convert(rows);
  }

  Future<void> _saveExcelCsvToDevice() async {
    try {
      final csvText = await _buildCsvText();
      if (csvText.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('내보낼 고객 데이터가 없습니다.')),
        );
        return;
      }

      final todayStr = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final fileName = '다온시스템_고객관리_$todayStr.csv';

      final bool saved = await _overlayChannel.invokeMethod('saveCsvFile', {
        'fileName': fileName,
        'csvText': csvText,
      }) ?? false;

      if (saved && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ [$fileName] 파일이 스마트폰에 저장되었습니다.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('파일 저장 오류: $e')),
      );
    }
  }

  Future<void> _shareExcelCsv() async {
    try {
      final csvText = await _buildCsvText();
      if (csvText.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('내보낼 고객 데이터가 없습니다.')),
        );
        return;
      }

      final todayStr = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final fileName = 'daon_crm_$todayStr.csv';

      await _overlayChannel.invokeMethod('shareCsvFile', {
        'fileName': fileName,
        'csvText': csvText,
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('공유 오류: $e')),
      );
    }
  }

  Future<void> _importFromExcelCsv() async {
    try {
      final String? rawContent = await _overlayChannel.invokeMethod('pickCsvContent');
      if (rawContent == null || rawContent.trim().isEmpty) return;

      String content = rawContent;
      if (content.startsWith('\uFEFF')) {
        content = content.substring(1);
      }

      final rows = const CsvToListConverter(eol: '\n').convert(content);
      if (rows.isEmpty) return;

      int importedCount = 0;
      for (int i = 0; i < rows.length; i++) {
        final row = rows[i];
        if (row.length < 3) continue;

        final col0 = row[0].toString().trim();
        final col1 = row[1].toString().trim();
        final col2 = row[2].toString().trim();

        if (i == 0 && (col0.contains('일자') || col1.contains('구분') || col2.contains('고객'))) {
          continue;
        }

        final isV2Format = (col1 == '개인' || col1 == '회사');
        final c = isV2Format
            ? Customer(
                visitDate: col0.isNotEmpty ? col0 : DateFormat('yyyy-MM-dd').format(DateTime.now()),
                customerType: col1,
                name: col2.isNotEmpty ? col2 : '이름미상',
                phone: row.length > 3 ? KoreanPhoneFormatter.formatNumber(row[3].toString().trim()) : '',
                address: row.length > 4 ? row[4].toString().trim() : '',
                device: row.length > 5 ? row[5].toString().trim() : '',
                symptom: row.length > 6 ? row[6].toString().trim() : '',
                amount: row.length > 7 ? row[7].toString().trim() : '0',
                materialCost: row.length > 8 ? row[8].toString().trim() : '0',
                paymentStatus: row.length > 13 && row[13].toString().trim().isNotEmpty ? row[13].toString().trim() : '입금완료',
                memo: row.length > 14 ? row[14].toString().trim() : '',
              )
            : Customer(
                visitDate: col0.isNotEmpty ? col0 : DateFormat('yyyy-MM-dd').format(DateTime.now()),
                customerType: '개인',
                name: col1.isNotEmpty ? col1 : '이름미상',
                phone: KoreanPhoneFormatter.formatNumber(col2),
                address: row.length > 3 ? row[3].toString().trim() : '',
                device: row.length > 4 ? row[4].toString().trim() : '',
                symptom: row.length > 5 ? row[5].toString().trim() : '',
                amount: row.length > 6 ? row[6].toString().trim() : '0',
                materialCost: row.length > 7 ? row[7].toString().trim() : '0',
                paymentStatus: row.length > 9 && row[9].toString().trim().isNotEmpty ? row[9].toString().trim() : '입금완료',
                memo: row.length > 10 ? row[10].toString().trim() : '',
              );

        await DatabaseHelper.instance.insertCustomer(c);
        importedCount++;
      }

      await _refreshCustomers(_searchController.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ 엑셀(CSV)에서 $importedCount건의 고객 정보를 불러왔습니다.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('불러오기 실패: CSV 파일 형식을 확인해 주세요. ($e)')),
      );
    }
  }

  Future<void> _confirmAndDeleteCustomer(Customer c, {bool closeSheet = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('고객 내역 삭제'),
        content: Text('[${c.name}] 고객님의 기록을 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok == true && c.id != null) {
      await DatabaseHelper.instance.deleteCustomer(c.id!);
      if (closeSheet && mounted) Navigator.pop(context);
      setState(() => _selectedCustomer = null);
      await _refreshCustomers(_searchController.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('삭제되었습니다.')));
      }
    }
  }

  void _showCustomerForm([Customer? customer]) {
    String customerType = customer?.customerType.isNotEmpty == true ? customer!.customerType : '개인';
    final nameCtrl = TextEditingController(text: customer?.name ?? '');
    final phoneCtrl = TextEditingController(
      text: customer != null ? KoreanPhoneFormatter.formatNumber(customer.phone) : '',
    );
    final addressCtrl = TextEditingController(text: customer?.address ?? '');
    final deviceCtrl = TextEditingController(text: customer?.device ?? '');
    final symptomCtrl = TextEditingController(text: customer?.symptom ?? '');
    final amountCtrl = TextEditingController(text: customer?.amount ?? '');
    final materialCtrl = TextEditingController(text: customer?.materialCost == '0' ? '' : (customer?.materialCost ?? ''));
    String paymentStatus = customer?.paymentStatus.isNotEmpty == true ? customer!.paymentStatus : '입금완료';
    final memoCtrl = TextEditingController(text: customer?.memo ?? '');
    final dateCtrl = TextEditingController(
      text: customer?.visitDate ?? DateFormat('yyyy-MM-dd').format(DateTime.now()),
    );

    Map<String, int> calcTaxAndProfit() {
      final total = int.tryParse(amountCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final mat = int.tryParse(materialCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final grossProfit = total - mat;
      final vat = (total / 11).round();
      final cardFee = paymentStatus == '카드결제' ? (total * 0.015).round() : 0;
      final taxable = grossProfit - vat - cardFee;
      final incomeTax = taxable > 0 ? (taxable * 0.15).round() : 0;
      final afterTax = grossProfit - vat - cardFee - incomeTax;
      return {
        'gross': grossProfit,
        'vat': vat,
        'cardFee': cardFee,
        'incomeTax': incomeTax,
        'afterTax': afterTax,
      };
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final taxInfo = calcTaxAndProfit();
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              left: 20,
              right: 20,
              top: 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        customer == null ? '신규 고객 및 수리 등록' : '고객 정보 수정',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      if (customer != null)
                        TextButton.icon(
                          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                          label: const Text('삭제', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                          onPressed: () => _confirmAndDeleteCustomer(customer, closeSheet: true),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  Row(
                    children: [
                      const Text('고객 구분: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('👤 개인'),
                        selected: customerType == '개인',
                        onSelected: (_) => setModalState(() => customerType = '개인'),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('🏢 회사(기업)'),
                        selected: customerType == '회사',
                        onSelected: (_) => setModalState(() => customerType = '회사'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '고객명 / 상호 *', border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [KoreanPhoneFormatter()],
                    decoration: const InputDecoration(
                      labelText: '전화번호 (숫자만 입력 시 자동 하이픈) *',
                      hintText: '01012345678',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('방문 지역 / 전체 주소', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      TextButton.icon(
                        icon: const Icon(Icons.content_paste_go, size: 16),
                        label: const Text('복사한 문자에서 주소 추출', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          final clip = await Clipboard.getData(Clipboard.kTextPlain);
                          final raw = clip?.text ?? '';
                          if (raw.isEmpty) return;

                          final pureAddr = _extractPureKoreanAddress(raw);
                          if (pureAddr.isNotEmpty) {
                            addressCtrl.text = pureAddr;
                          }
                          final phoneMatch = RegExp(r'01[016789]-?\d{3,4}-?\d{4}').firstMatch(raw);
                          if (phoneMatch != null && phoneCtrl.text.isEmpty) {
                            phoneCtrl.text = KoreanPhoneFormatter.formatNumber(phoneMatch.group(0)!);
                          }
                          if (nameCtrl.text.isEmpty && pureAddr.isNotEmpty) {
                            final parts = pureAddr.split(' ');
                            if (parts.length >= 3) {
                              nameCtrl.text = '${parts[1]} ${parts[2]} 고객님';
                            }
                          }
                        },
                      ),
                    ],
                  ),
                  TextField(
                    controller: addressCtrl,
                    maxLines: 2,
                    minLines: 1,
                    decoration: const InputDecoration(hintText: '상세 동·호수까지 전체 주소 입력', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: deviceCtrl, decoration: const InputDecoration(labelText: '기종 (노트북, 데스크톱, 서버 등)', border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                  TextField(controller: symptomCtrl, decoration: const InputDecoration(labelText: '고장 증상 및 작업 내역', border: OutlineInputBorder())),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: amountCtrl,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setModalState(() {}),
                          decoration: const InputDecoration(labelText: '총 청구금액(원)', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: materialCtrl,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setModalState(() {}),
                          decoration: const InputDecoration(labelText: '자재비/부품원가(원)', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '세전 순수익: ${_numFormat.format(taxInfo['gross'])}원',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            DropdownButton<String>(
                              value: paymentStatus,
                              underline: const SizedBox(),
                              items: ['입금완료', '미수금', '카드결제', '현금영수증']
                                  .map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))))
                                  .toList(),
                              onChanged: (val) => setModalState(() => paymentStatus = val!),
                            ),
                          ],
                        ),
                        const Divider(height: 10),
                        Text(
                          '• 예상 부가세(10%): -${_numFormat.format(taxInfo['vat'])}원   |   카드수수료(1.5%): -${_numFormat.format(taxInfo['cardFee'])}원',
                          style: const TextStyle(fontSize: 11, color: Colors.black87),
                        ),
                        Text(
                          '• 예상 소득세 적립(15%): -${_numFormat.format(taxInfo['incomeTax'])}원',
                          style: const TextStyle(fontSize: 11, color: Colors.black87),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '💰 세후 실질 순수익: ${_numFormat.format(taxInfo['afterTax'])}원',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFD32F2F), fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: dateCtrl, decoration: const InputDecoration(labelText: '방문일자 (YYYY-MM-DD)', border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                  TextField(controller: memoCtrl, maxLines: 2, decoration: const InputDecoration(labelText: '특이사항 / A/S 메모', border: OutlineInputBorder())),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD32F2F), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: () async {
                      if (nameCtrl.text.isEmpty || phoneCtrl.text.isEmpty) return;
                      final newCustomer = Customer(
                        id: customer?.id,
                        customerType: customerType,
                        name: nameCtrl.text.trim(),
                        phone: KoreanPhoneFormatter.formatNumber(phoneCtrl.text.trim()),
                        address: addressCtrl.text.trim(),
                        device: deviceCtrl.text.trim(),
                        symptom: symptomCtrl.text.trim(),
                        amount: amountCtrl.text.trim(),
                        materialCost: materialCtrl.text.trim().isEmpty ? '0' : materialCtrl.text.trim(),
                        paymentStatus: paymentStatus,
                        memo: memoCtrl.text.trim(),
                        visitDate: dateCtrl.text.trim(),
                      );
                      if (customer == null) {
                        await DatabaseHelper.instance.insertCustomer(newCustomer);
                      } else {
                        await DatabaseHelper.instance.updateCustomer(newCustomer);
                      }
                      if (!mounted) return;
                      Navigator.pop(ctx);
                      _refreshCustomers(_searchController.text);
                    },
                    child: const Text('저장하기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailPane(Customer c, {bool isBottomSheet = false}) {
    return Card(
      margin: const EdgeInsets.all(14),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: c.customerType == '회사' ? Colors.indigo.shade50 : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            c.customerType == '회사' ? '🏢 회사(기업)' : '👤 개인 고객',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.customerType == '회사' ? Colors.indigo : Colors.black87),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(c.name, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        tooltip: '전화걸기',
                        icon: const Icon(Icons.call, color: Colors.green),
                        onPressed: () => launchUrl(Uri.parse('tel:${c.phone}')),
                      ),
                      IconButton(
                        tooltip: '문자보내기',
                        icon: const Icon(Icons.sms_outlined, color: Color(0xFFD32F2F)),
                        onPressed: () => _sendSmsToCustomer(c),
                      ),
                      IconButton(
                        tooltip: '수정',
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () {
                          if (isBottomSheet) Navigator.pop(context);
                          _showCustomerForm(c);
                        },
                      ),
                      IconButton(
                        tooltip: '삭제',
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => _confirmAndDeleteCustomer(c, closeSheet: isBottomSheet),
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(),
              Row(
                children: [
                  Expanded(child: Text('📞 연락처: ${c.phone}', style: const TextStyle(fontSize: 16))),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.message, size: 15, color: Color(0xFFD32F2F)),
                    label: const Text('문자 바로보내기', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFD32F2F))),
                    onPressed: () => _sendSmsToCustomer(c),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: Text('📍 주소: ${c.address}', style: const TextStyle(fontSize: 15))),
                  if (c.address.isNotEmpty)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF03C75A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      icon: const Icon(Icons.navigation, size: 16),
                      label: const Text('네이버지도 길안내', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: () => _openNaverMapApp(c.address),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text('💻 기종: ${c.device}', style: const TextStyle(fontSize: 15)),
              const SizedBox(height: 8),
              Text('🛠 작업내역: ${c.symptom}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade100),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            const Text('총 청구금액', style: TextStyle(fontSize: 12, color: Colors.black54)),
                            const SizedBox(height: 4),
                            Text('${_numFormat.format(c.amountInt)}원', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ],
                        ),
                        Column(
                          children: [
                            const Text('자재비', style: TextStyle(fontSize: 12, color: Colors.black54)),
                            const SizedBox(height: 4),
                            Text('-${_numFormat.format(c.materialCostInt)}원', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.redAccent)),
                          ],
                        ),
                        Column(
                          children: [
                            const Text('세전 순수익', style: TextStyle(fontSize: 12, color: Colors.black54)),
                            const SizedBox(height: 4),
                            Text('${_numFormat.format(c.netProfit)}원', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFFD32F2F))),
                          ],
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('부가세(10%): -${_numFormat.format(c.estimatedVat)}원', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                        Text('카드수수료: -${_numFormat.format(c.estimatedCardFee)}원', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                        Text('소득세(15%): -${_numFormat.format(c.estimatedIncomeTax)}원', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('💰 세후 실질 순수익', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
                        Text('${_numFormat.format(c.afterTaxNetProfit)}원', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.teal)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text('💳 결제상태: ${c.paymentStatus}   |   📅 방문일: ${c.visitDate}', style: const TextStyle(fontSize: 13, color: Colors.black54)),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                child: Text('📝 메모: ${c.memo}'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonthlyReportView() {
    final Set<String> monthSet = {DateFormat('yyyy-MM').format(DateTime.now())};
    for (final c in _customers) {
      if (c.visitDate.length >= 7) {
        monthSet.add(c.visitDate.substring(0, 7));
      }
    }
    final months = monthSet.toList()..sort((a, b) => b.compareTo(a));
    if (!months.contains(_selectedMonth)) {
      _selectedMonth = months.first;
    }

    final monthlyList = _customers.where((c) => c.visitDate.startsWith(_selectedMonth)).toList();
    int totalSales = 0;
    int totalMaterial = 0;
    int totalVat = 0;
    int totalCardFee = 0;
    int totalIncomeTax = 0;
    int totalUnpaid = 0;

    for (final c in monthlyList) {
      totalSales += c.amountInt;
      totalMaterial += c.materialCostInt;
      totalVat += c.estimatedVat;
      totalCardFee += c.estimatedCardFee;
      totalIncomeTax += c.estimatedIncomeTax;
      if (c.paymentStatus == '미수금') {
        totalUnpaid += c.amountInt;
      }
    }
    final totalGrossProfit = totalSales - totalMaterial;
    final totalAfterTax = totalGrossProfit - totalVat - totalCardFee - totalIncomeTax;

    return Column(
      children: [
        Container(
          color: Colors.red.shade50,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('📅 정산 월 선택', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              DropdownButton<String>(
                value: _selectedMonth,
                items: months.map((m) => DropdownMenuItem(value: m, child: Text('$m 월', style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
                onChanged: (val) => setState(() => _selectedMonth = val!),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('$_selectedMonth 총 매출 (${monthlyList.length}건)', style: const TextStyle(fontSize: 15, color: Colors.black87)),
                      Text('${_numFormat.format(totalSales)}원', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('총 자재비 (부품원가)', style: TextStyle(fontSize: 13, color: Colors.black54)),
                      Text('-${_numFormat.format(totalMaterial)}원', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.redAccent)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('예상 부가세 + 카드수수료 + 소득세', style: TextStyle(fontSize: 12, color: Colors.black54)),
                      Text('-${_numFormat.format(totalVat + totalCardFee + totalIncomeTax)}원', style: const TextStyle(fontSize: 13, color: Colors.orange)),
                    ],
                  ),
                  const Divider(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('세전 순수익 합계', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      Text('${_numFormat.format(totalGrossProfit)}원', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFD32F2F))),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('💰 세후 실질 순수익', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.teal)),
                      Text('${_numFormat.format(totalAfterTax)}원', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal)),
                    ],
                  ),
                  if (totalUnpaid > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('⚠️ 해당 월 미수금 잔액', style: TextStyle(fontSize: 13, color: Colors.red)),
                        Text('${_numFormat.format(totalUnpaid)}원', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: monthlyList.isEmpty
              ? const Center(child: Text('해당 월에 등록된 매출 내역이 없습니다.'))
              : ListView.separated(
                  itemCount: monthlyList.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final c = monthlyList[i];
                    return ListTile(
                      title: Text('${c.visitDate} · [${c.customerType}] ${c.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Text('${c.symptom} (자재비: ${_numFormat.format(c.materialCostInt)}원)'),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('세후 ${_numFormat.format(c.afterTaxNetProfit)}원', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 13)),
                          Text('청구 ${_numFormat.format(c.amountInt)}원', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWideScreen = MediaQuery.of(context).size.width >= 600;
    final permReady = _hasOverlayPerm && _hasPhonePerm;
    final displayedList = _filteredAndSortedCustomers;

    final unpaidList = _customers.where((c) => c.paymentStatus == '미수금').toList();
    final totalUnpaidSum = unpaidList.fold<int>(0, (sum, c) => sum + c.amountInt);

    final listWidget = Column(
      children: [
        Container(
          color: permReady ? Colors.green.shade50 : Colors.amber.shade100,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              Icon(permReady ? Icons.check_circle : Icons.warning_amber_rounded,
                  size: 18, color: permReady ? Colors.green : Colors.orange.shade900),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  permReady ? '원 UI 9 수신 팝업 대기중' : '원 UI 9 수신 팝업 설정 필요',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: permReady ? Colors.green.shade900 : Colors.orange.shade900),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), minimumSize: Size.zero),
                onPressed: _showSamsungRestrictedGuide,
                child: const Text('필수설정 안내', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFD32F2F))),
              ),
              TextButton(
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), minimumSize: Size.zero),
                onPressed: () async {
                  await _overlayChannel.invokeMethod('testPopup', {
                    'phone': _customers.isNotEmpty ? _customers.first.phone : '010-1234-5678',
                  });
                },
                child: const Text('팝업 테스트', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: TextField(
            controller: _searchController,
            onChanged: (val) => _refreshCustomers(val),
            decoration: InputDecoration(
              hintText: '고객명, 전화번호, 지역, 수리내역 검색',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              filled: true,
              fillColor: Colors.grey.shade100,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
        ),

        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            children: [
              FilterChip(
                label: Text(
                  '⚠️ 미수금만 (${unpaidList.length}건 / ${_numFormat.format(totalUnpaidSum)}원)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: _onlyUnpaid ? Colors.white : Colors.red.shade800,
                  ),
                ),
                selected: _onlyUnpaid,
                selectedColor: Colors.red.shade700,
                backgroundColor: Colors.red.shade50,
                onSelected: (val) => setState(() => _onlyUnpaid = val),
              ),
              const SizedBox(width: 6),

              ChoiceChip(
                label: const Text('전체', style: TextStyle(fontSize: 11)),
                selected: _typeFilter == '전체',
                onSelected: (_) => setState(() => _typeFilter = '전체'),
              ),
              const SizedBox(width: 4),
              ChoiceChip(
                label: const Text('🏢 회사', style: TextStyle(fontSize: 11)),
                selected: _typeFilter == '회사',
                onSelected: (_) => setState(() => _typeFilter = '회사'),
              ),
              const SizedBox(width: 4),
              ChoiceChip(
                label: const Text('👤 개인', style: TextStyle(fontSize: 11)),
                selected: _typeFilter == '개인',
                onSelected: (_) => setState(() => _typeFilter = '개인'),
              ),
              const SizedBox(width: 8),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: DropdownButton<String>(
                  value: _sortBy,
                  underline: const SizedBox(),
                  isDense: true,
                  style: const TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.bold),
                  items: const [
                    DropdownMenuItem(value: 'date_desc', child: Text('정렬: 최신날짜순')),
                    DropdownMenuItem(value: 'date_asc', child: Text('정렬: 오래된날짜순')),
                    DropdownMenuItem(value: 'amount_desc', child: Text('정렬: 금액높은순')),
                    DropdownMenuItem(value: 'amount_asc', child: Text('정렬: 금액낮은순')),
                  ],
                  onChanged: (val) => setState(() => _sortBy = val!),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: displayedList.isEmpty
              ? Center(
                  child: Text(
                    _onlyUnpaid ? '미수금 내역이 없습니다.' : '조건에 맞는 고객 내역이 없습니다.',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.separated(
                  itemCount: displayedList.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final c = displayedList[i];
                    return ListTile(
                      title: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: c.customerType == '회사' ? Colors.indigo.shade100 : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              c.customerType,
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: c.customerType == '회사' ? Colors.indigo.shade900 : Colors.black87),
                            ),
                          ),
                          Expanded(
                            child: Text('${c.name} (${c.phone})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                      subtitle: Text('${c.visitDate} · ${c.address}\n청구 ${_numFormat.format(c.amountInt)}원 | 세후순수익 ${_numFormat.format(c.afterTaxNetProfit)}원'),
                      isThreeLine: true,
                      trailing: Chip(
                        label: Text(c.paymentStatus, style: const TextStyle(fontSize: 11)),
                        backgroundColor: c.paymentStatus == '미수금' ? Colors.red.shade100 : Colors.red.shade50,
                      ),
                      onTap: () {
                        if (isWideScreen) {
                          setState(() => _selectedCustomer = c);
                        } else {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) => SizedBox(
                              height: MediaQuery.of(context).size.height * 0.78,
                              child: _buildDetailPane(c, isBottomSheet: true),
                            ),
                          );
                        }
                      },
                    );
                  },
                ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('다온시스템 고객관리', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFD32F2F),
        foregroundColor: Colors.white,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.table_view_rounded),
            tooltip: '엑셀(CSV) 내보내기 / 불러오기',
            onSelected: (value) {
              if (value == 'save') {
                _saveExcelCsvToDevice();
              } else if (value == 'share') {
                _shareExcelCsv();
              } else if (value == 'import') {
                _importFromExcelCsv();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'save',
                child: Row(
                  children: [
                    Icon(Icons.save_alt, color: Colors.green),
                    SizedBox(width: 8),
                    Text('엑셀(CSV) 내 파일에 저장'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'share',
                child: Row(
                  children: [
                    Icon(Icons.share, color: Colors.teal),
                    SizedBox(width: 8),
                    Text('엑셀(CSV) 카톡/메일 공유'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'import',
                child: Row(
                  children: [
                    Icon(Icons.download_for_offline, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('엑셀(CSV) 불러오기'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _tabIndex == 1
          ? _buildMonthlyReportView()
          : (isWideScreen
              ? Row(
                  children: [
                    Expanded(flex: 1, child: listWidget),
                    const VerticalDivider(width: 1),
                    Expanded(
                      flex: 1,
                      child: _selectedCustomer != null
                          ? _buildDetailPane(_selectedCustomer!)
                          : const Center(child: Text('좌측에서 고객을 선택하면 상세 내역이 표시됩니다.')),
                    ),
                  ],
                )
              : listWidget),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (idx) => setState(() => _tabIndex = idx),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: '고객 관리'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: '월별 매출 정산'),
        ],
      ),
      floatingActionButton: _tabIndex == 0
          ? FloatingActionButton.extended(
              onPressed: () => _showCustomerForm(),
              backgroundColor: const Color(0xFFD32F2F),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('고객 등록'),
            )
          : null,
    );
  }
}