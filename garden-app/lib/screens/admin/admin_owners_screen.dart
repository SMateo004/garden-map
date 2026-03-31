import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../theme/garden_theme.dart';

class AdminOwnersScreen extends StatefulWidget {
  final String adminToken;
  const AdminOwnersScreen({super.key, required this.adminToken});

  @override
  State<AdminOwnersScreen> createState() => _AdminOwnersScreenState();
}

class _AdminOwnersScreenState extends State<AdminOwnersScreen> {
  List<Map<String, dynamic>> _owners = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _page = 1;
  int _totalPages = 1;
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  String _searchQuery = '';

  String get _baseUrl => const String.fromEnvironment(
        'API_URL',
        defaultValue: 'http://localhost:3000/api',
      );

  @override
  void initState() {
    super.initState();
    _loadOwners();
    _scrollCtrl.addListener(() {
      if (_scrollCtrl.position.pixels >=
              _scrollCtrl.position.maxScrollExtent - 100 &&
          !_isLoadingMore &&
          _page < _totalPages) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOwners({bool reset = false}) async {
    if (reset) {
      setState(() {
        _page = 1;
        _owners = [];
        _isLoading = true;
      });
    }
    try {
      String url =
          '$_baseUrl/admin/owners?page=$_page&limit=20';
      if (_searchQuery.isNotEmpty) url += '&search=$_searchQuery';
      final res = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer ${widget.adminToken}'},
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        setState(() {
          _owners = (data['data']['owners'] as List)
              .cast<Map<String, dynamic>>();
          _totalPages = data['data']['pages'] ?? 1;
        });
      }
    } catch (e) {
      debugPrint('Error loading owners: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    setState(() {
      _isLoadingMore = true;
      _page++;
    });
    try {
      String url =
          '$_baseUrl/admin/owners?page=$_page&limit=20';
      if (_searchQuery.isNotEmpty) url += '&search=$_searchQuery';
      final res = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer ${widget.adminToken}'},
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        setState(() {
          _owners.addAll(
              (data['data']['owners'] as List).cast<Map<String, dynamic>>());
        });
      }
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  void _openOwnerDetail(Map<String, dynamic> owner) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OwnerDetailSheet(
        ownerId: owner['id'] as String,
        adminToken: widget.adminToken,
        baseUrl: _baseUrl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkBackground : GardenColors.lightBackground;
    final surface = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return Column(
      children: [
        // Header stats bar
        Container(
          color: surface,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  style: TextStyle(color: textColor, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre o email…',
                    hintStyle: TextStyle(color: subtextColor, fontSize: 13),
                    prefixIcon: Icon(Icons.search_rounded, color: subtextColor, size: 18),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear_rounded, size: 16, color: subtextColor),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                              _loadOwners(reset: true);
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: isDark ? GardenColors.darkBackground : GardenColors.lightBackground,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: GardenColors.primary),
                    ),
                  ),
                  onSubmitted: (v) {
                    setState(() => _searchQuery = v.trim());
                    _loadOwners(reset: true);
                  },
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                color: GardenColors.primary,
                onPressed: () => _loadOwners(reset: true),
                tooltip: 'Recargar',
              ),
            ],
          ),
        ),
        // List
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: GardenColors.primary))
              : _owners.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('🐾', style: TextStyle(fontSize: 40)),
                          const SizedBox(height: 12),
                          Text('No hay dueños registrados',
                              style: TextStyle(color: subtextColor, fontSize: 14)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      color: GardenColors.primary,
                      onRefresh: () => _loadOwners(reset: true),
                      child: ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.all(16),
                        itemCount: _owners.length + (_isLoadingMore ? 1 : 0),
                        itemBuilder: (ctx, i) {
                          if (i == _owners.length) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(
                                    color: GardenColors.primary, strokeWidth: 2),
                              ),
                            );
                          }
                          final owner = _owners[i];
                          return _OwnerCard(
                            owner: owner,
                            onTap: () => _openOwnerDetail(owner),
                            isDark: isDark,
                            textColor: textColor,
                            subtextColor: subtextColor,
                            borderColor: borderColor,
                            surface: surface,
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Owner Card
// ─────────────────────────────────────────────────────────────────────────────

class _OwnerCard extends StatelessWidget {
  final Map<String, dynamic> owner;
  final VoidCallback onTap;
  final bool isDark;
  final Color textColor, subtextColor, borderColor, surface;

  const _OwnerCard({
    required this.owner,
    required this.onTap,
    required this.isDark,
    required this.textColor,
    required this.subtextColor,
    required this.borderColor,
    required this.surface,
  });

  @override
  Widget build(BuildContext context) {
    final name = owner['name'] as String? ?? '—';
    final email = owner['email'] as String? ?? '—';
    final photo = owner['photoUrl'] as String?;
    final petsCount = owner['petsCount'] as int? ?? 0;
    final bookingsCount = owner['bookingsCount'] as int? ?? 0;
    final completedBookings = owner['completedBookings'] as int? ?? 0;
    final totalSpent = (owner['totalSpent'] as num?)?.toDouble() ?? 0.0;
    final isComplete = owner['isComplete'] as bool? ?? false;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            // Avatar
            Stack(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundImage: photo != null ? NetworkImage(photo) : null,
                  backgroundColor: GardenColors.primary.withValues(alpha: 0.12),
                  child: photo == null
                      ? Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(
                              color: GardenColors.primary,
                              fontWeight: FontWeight.w800,
                              fontSize: 18),
                        )
                      : null,
                ),
                if (isComplete)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: const BoxDecoration(
                        color: GardenColors.success,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check, size: 9, color: Colors.white),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(email,
                      style: TextStyle(
                          color: subtextColor, fontSize: 11),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _chip('🐾 $petsCount mascotas', GardenColors.primary),
                      const SizedBox(width: 6),
                      _chip('📋 $completedBookings/$bookingsCount', GardenColors.success),
                    ],
                  ),
                ],
              ),
            ),
            // Total
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Bs ${totalSpent.toStringAsFixed(0)}',
                    style: const TextStyle(
                        color: GardenColors.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 13)),
                const SizedBox(height: 4),
                Icon(Icons.chevron_right_rounded, color: subtextColor, size: 18),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Owner Detail Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _OwnerDetailSheet extends StatefulWidget {
  final String ownerId;
  final String adminToken;
  final String baseUrl;

  const _OwnerDetailSheet({
    required this.ownerId,
    required this.adminToken,
    required this.baseUrl,
  });

  @override
  State<_OwnerDetailSheet> createState() => _OwnerDetailSheetState();
}

class _OwnerDetailSheetState extends State<_OwnerDetailSheet>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _data;
  bool _isLoading = true;
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _loadDetail();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDetail() async {
    try {
      final res = await http.get(
        Uri.parse('${widget.baseUrl}/admin/owners/${widget.ownerId}'),
        headers: {'Authorization': 'Bearer ${widget.adminToken}'},
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        setState(() => _data = data['data']);
      }
    } catch (e) {
      debugPrint(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = themeNotifier.isDark;
    final bg = isDark ? GardenColors.darkSurface : GardenColors.lightSurface;
    final textColor = isDark ? GardenColors.darkTextPrimary : GardenColors.lightTextPrimary;
    final subtextColor = isDark ? GardenColors.darkTextSecondary : GardenColors.lightTextSecondary;
    final borderColor = isDark ? GardenColors.darkBorder : GardenColors.lightBorder;

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      // ignore: use_decorated_box
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: subtextColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_isLoading)
            const Expanded(
              child: Center(
                  child: CircularProgressIndicator(color: GardenColors.primary)),
            )
          else if (_data == null)
            Expanded(
              child: Center(
                child: Text('Error al cargar',
                    style: TextStyle(color: subtextColor)),
              ),
            )
          else
            Expanded(
              child: Column(
                children: [
                  // Profile header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _buildHeader(textColor, subtextColor, borderColor),
                  ),
                  const SizedBox(height: 12),
                  // Tabs
                  Container(
                    decoration: BoxDecoration(
                      border: Border(
                          bottom: BorderSide(color: borderColor, width: 0.5)),
                    ),
                    child: TabBar(
                      controller: _tabCtrl,
                      labelColor: GardenColors.primary,
                      unselectedLabelColor: subtextColor,
                      labelStyle: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700),
                      indicatorColor: GardenColors.primary,
                      indicatorWeight: 2,
                      tabs: const [
                        Tab(text: 'Mascotas'),
                        Tab(text: 'Reservas'),
                        Tab(text: 'Estadísticas'),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabCtrl,
                      children: [
                        _buildPetsTab(textColor, subtextColor, borderColor),
                        _buildBookingsTab(textColor, subtextColor, borderColor),
                        _buildStatsTab(textColor, subtextColor, borderColor),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(Color textColor, Color subtextColor, Color borderColor) {
    final name = _data!['name'] as String? ?? '—';
    final email = _data!['email'] as String? ?? '—';
    final phone = _data!['phone'] as String?;
    final photo = _data!['photoUrl'] as String?;
    final verified = _data!['emailVerified'] as bool? ?? false;
    final createdAt = _data!['createdAt'] as String? ?? '';

    return Row(
      children: [
        CircleAvatar(
          radius: 34,
          backgroundImage: photo != null ? NetworkImage(photo) : null,
          backgroundColor: GardenColors.primary.withValues(alpha: 0.12),
          child: photo == null
              ? Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(
                      color: GardenColors.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 22),
                )
              : null,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(name,
                        style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 17),
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 8),
                  if (verified)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: GardenColors.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Text('Verificado',
                          style: TextStyle(
                              color: GardenColors.success,
                              fontSize: 9,
                              fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(email,
                  style: TextStyle(color: subtextColor, fontSize: 12),
                  overflow: TextOverflow.ellipsis),
              if (phone != null) ...[
                const SizedBox(height: 2),
                Text(phone,
                    style: TextStyle(color: subtextColor, fontSize: 11)),
              ],
              const SizedBox(height: 4),
              Text(
                'Miembro desde ${_formatDate(createdAt)}',
                style: TextStyle(color: subtextColor, fontSize: 10),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPetsTab(Color textColor, Color subtextColor, Color borderColor) {
    final pets = (_data!['clientProfile']?['pets'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];

    if (pets.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🐶', style: TextStyle(fontSize: 36)),
            const SizedBox(height: 10),
            Text('Sin mascotas registradas',
                style: TextStyle(color: subtextColor, fontSize: 13)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: pets.length,
      itemBuilder: (ctx, i) {
        final pet = pets[i];
        final petName = pet['name'] as String? ?? '—';
        final breed = pet['breed'] as String?;
        final size = pet['size'] as String?;
        final photo = pet['photoUrl'] as String?;
        final notes = pet['notes'] as String?;
        final gender = pet['gender'] as String?;
        final weight = pet['weight'];
        final sterilized = pet['sterilized'] as bool?;
        final microchip = pet['microchipNumber'] as String?;
        final specialNeeds = pet['specialNeeds'] as String?;
        final extraPhotos = (pet['extraPhotos'] as List?)?.cast<String>() ?? [];
        final vaccinePhotos = (pet['vaccinePhotos'] as List?)?.cast<String>() ?? [];
        final documents = (pet['documents'] as List?)?.cast<String>() ?? [];
        final bg2 = themeNotifier.isDark ? GardenColors.darkBackground : GardenColors.lightBackground;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: bg2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pet header
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundImage: photo != null ? NetworkImage(fixImageUrl(photo)) : null,
                      backgroundColor: GardenColors.accent.withValues(alpha: 0.15),
                      child: photo == null
                          ? Text(
                              petName.isNotEmpty ? petName[0].toUpperCase() : '🐾',
                              style: const TextStyle(color: GardenColors.accent, fontWeight: FontWeight.bold, fontSize: 20),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(petName, style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 15)),
                          if (breed != null) ...[
                            const SizedBox(height: 2),
                            Text(breed, style: TextStyle(color: subtextColor, fontSize: 12)),
                          ],
                          const SizedBox(height: 6),
                          Wrap(spacing: 6, runSpacing: 4, children: [
                            if (size != null) _sizeChip(size),
                            if (gender == 'MALE') _infoChip('♂ Macho', GardenColors.secondary),
                            if (gender == 'FEMALE') _infoChip('♀ Hembra', GardenColors.accent),
                            if (weight != null) _infoChip('${weight}kg', GardenColors.primary),
                            if (sterilized == true) _infoChip('Esterilizado', GardenColors.success),
                          ]),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Extra info
              if (microchip != null || specialNeeds != null || notes != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (microchip != null && microchip.isNotEmpty)
                        _petInfoRow(Icons.memory_outlined, 'Microchip: $microchip', subtextColor),
                      if (specialNeeds != null && specialNeeds.isNotEmpty)
                        _petInfoRow(Icons.medical_services_outlined, specialNeeds, subtextColor),
                      if (notes != null && notes.isNotEmpty)
                        _petInfoRow(Icons.notes_outlined, notes, subtextColor),
                    ],
                  ),
                ),
              // Fotos adicionales
              if (extraPhotos.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                  child: Text('Fotos adicionales (${extraPhotos.length})',
                    style: TextStyle(color: subtextColor, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
                SizedBox(
                  height: 70,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                    itemCount: extraPhotos.length,
                    itemBuilder: (_, j) => Container(
                      width: 60, height: 60,
                      margin: const EdgeInsets.only(right: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(fixImageUrl(extraPhotos[j]), fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: GardenColors.primary.withValues(alpha: 0.1),
                            child: const Icon(Icons.pets, size: 20, color: GardenColors.primary),
                          )),
                      ),
                    ),
                  ),
                ),
              ],
              // Fotos vacunas
              if (vaccinePhotos.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                  child: Text('Vacunas (${vaccinePhotos.length})',
                    style: TextStyle(color: subtextColor, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
                SizedBox(
                  height: 70,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                    itemCount: vaccinePhotos.length,
                    itemBuilder: (_, j) => Container(
                      width: 60, height: 60,
                      margin: const EdgeInsets.only(right: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(fixImageUrl(vaccinePhotos[j]), fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: GardenColors.success.withValues(alpha: 0.1),
                            child: const Icon(Icons.vaccines, size: 20, color: GardenColors.success),
                          )),
                      ),
                    ),
                  ),
                ),
              ],
              // Documentos
              if (documents.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                  child: Row(children: [
                    const Icon(Icons.insert_drive_file_outlined, size: 14, color: GardenColors.primary),
                    const SizedBox(width: 6),
                    Text('${documents.length} documento${documents.length > 1 ? 's' : ''} adjunto${documents.length > 1 ? 's' : ''}',
                      style: const TextStyle(color: GardenColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _sizeChip(String size) {
    final colors = {
      'SMALL': GardenColors.success,
      'MEDIUM': GardenColors.warning,
      'LARGE': GardenColors.error,
      'GIANT': const Color(0xFF8B0000),
    };
    final labels = {
      'SMALL': 'Pequeño',
      'MEDIUM': 'Mediano',
      'LARGE': 'Grande',
      'GIANT': 'Gigante',
    };
    final c = colors[size] ?? GardenColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Text(labels[size] ?? size,
          style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }

  Widget _infoChip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
  );

  Widget _petInfoRow(IconData icon, String text, Color color) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 6),
      Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis)),
    ]),
  );

  Widget _buildBookingsTab(
      Color textColor, Color subtextColor, Color borderColor) {
    final bookings = (_data!['bookings'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];

    if (bookings.isEmpty) {
      return Center(
        child: Text('Sin reservas', style: TextStyle(color: subtextColor)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: bookings.length,
      itemBuilder: (ctx, i) {
        final b = bookings[i];
        final status = b['status'] as String? ?? '';
        final serviceType = b['serviceType'] as String? ?? '';
        final total = (b['totalPrice'] as num?)?.toDouble() ?? 0.0;
        final caregiverName = b['caregiverName'] as String? ?? '—';
        final petName = b['petName'] as String? ?? '—';
        final date = b['walkDate'] as String? ?? b['createdAt'] as String? ?? '';

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: themeNotifier.isDark
                ? GardenColors.darkBackground
                : GardenColors.lightBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _statusColor(status).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(serviceType == 'PASEO' ? '🦮' : '🏠',
                      style: const TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          serviceType == 'PASEO' ? 'Paseo' : 'Hospedaje',
                          style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 12),
                        ),
                        const SizedBox(width: 8),
                        _bookingStatusBadge(status),
                      ],
                    ),
                    Text('Con $caregiverName · $petName',
                        style:
                            TextStyle(color: subtextColor, fontSize: 11)),
                    Text(_formatDate(date),
                        style:
                            TextStyle(color: subtextColor, fontSize: 10)),
                  ],
                ),
              ),
              Text(
                'Bs ${total.toStringAsFixed(0)}',
                style: const TextStyle(
                    color: GardenColors.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatsTab(
      Color textColor, Color subtextColor, Color borderColor) {
    final stats = _data!['stats'] as Map<String, dynamic>? ?? {};
    final totalBookings = stats['totalBookings'] as int? ?? 0;
    final completed = stats['completedBookings'] as int? ?? 0;
    final totalSpent = (stats['totalSpent'] as num?)?.toDouble() ?? 0.0;
    final petsCount =
        (_data!['clientProfile']?['pets'] as List?)?.length ?? 0;
    final completionRate =
        totalBookings > 0 ? (completed / totalBookings * 100) : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Stats grid
          Row(
            children: [
              Expanded(
                  child: _statCard('Total reservas', '$totalBookings',
                      Icons.calendar_today_rounded, GardenColors.primary,
                      textColor: textColor, subtextColor: subtextColor,
                      borderColor: borderColor)),
              const SizedBox(width: 10),
              Expanded(
                  child: _statCard('Completadas', '$completed',
                      Icons.check_circle_rounded, GardenColors.success,
                      textColor: textColor, subtextColor: subtextColor,
                      borderColor: borderColor)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                  child: _statCard('Total gastado',
                      'Bs ${totalSpent.toStringAsFixed(0)}',
                      Icons.payments_rounded, GardenColors.warning,
                      textColor: textColor, subtextColor: subtextColor,
                      borderColor: borderColor)),
              const SizedBox(width: 10),
              Expanded(
                  child: _statCard('Mascotas', '$petsCount',
                      Icons.pets_rounded, GardenColors.accent,
                      textColor: textColor, subtextColor: subtextColor,
                      borderColor: borderColor)),
            ],
          ),
          const SizedBox(height: 16),
          // Completion rate bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: themeNotifier.isDark
                  ? GardenColors.darkBackground
                  : GardenColors.lightBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Tasa de completado',
                        style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                    Text('${completionRate.toStringAsFixed(0)}%',
                        style: const TextStyle(
                            color: GardenColors.success,
                            fontWeight: FontWeight.w800,
                            fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: completionRate / 100,
                    backgroundColor: GardenColors.success.withValues(alpha: 0.1),
                    valueColor: const AlwaysStoppedAnimation(GardenColors.success),
                    minHeight: 8,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Profile completeness
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: themeNotifier.isDark
                  ? GardenColors.darkBackground
                  : GardenColors.lightBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Información de perfil',
                    style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                const SizedBox(height: 12),
                _infoRow('Perfil completo',
                    (_data!['clientProfile']?['isComplete'] as bool? ?? false)
                        ? 'Sí'
                        : 'No',
                    textColor, subtextColor),
                _infoRow(
                    'Zona',
                    _data!['clientProfile']?['zone'] as String? ?? '—',
                    textColor, subtextColor),
                _infoRow(
                    'Dirección',
                    _data!['clientProfile']?['address'] as String? ?? '—',
                    textColor, subtextColor),
                _infoRow(
                    'Email verificado',
                    (_data!['emailVerified'] as bool? ?? false) ? 'Sí' : 'No',
                    textColor, subtextColor),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color,
      {required Color textColor,
      required Color subtextColor,
      required Color borderColor}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: themeNotifier.isDark
            ? GardenColors.darkBackground
            : GardenColors.lightBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  color: textColor, fontWeight: FontWeight.w800, fontSize: 18)),
          Text(label,
              style: TextStyle(color: subtextColor, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, Color textColor, Color subtextColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: subtextColor, fontSize: 12)),
          Text(value,
              style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 12)),
        ],
      ),
    );
  }

  Widget _bookingStatusBadge(String status) {
    final map = {
      'COMPLETED': (GardenColors.success, 'Completada'),
      'IN_PROGRESS': (GardenColors.primary, 'En curso'),
      'CONFIRMED': (GardenColors.warning, 'Confirmada'),
      'CANCELLED': (GardenColors.error, 'Cancelada'),
    };
    final entry = map[status];
    final color = entry?.$1 ?? Colors.grey;
    final label = entry?.$2 ?? status;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'COMPLETED':
        return GardenColors.success;
      case 'IN_PROGRESS':
        return GardenColors.primary;
      case 'CANCELLED':
        return GardenColors.error;
      default:
        return GardenColors.warning;
    }
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '—';
    }
  }
}
