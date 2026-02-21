import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/marketplace_strategy.dart';
import '../services/user_profile_service.dart';
import '../utils/theme.dart';
import 'marketplace_screen.dart';

class PublisherProfileSheet extends StatelessWidget {
  final PublisherProfile profile;

  const PublisherProfileSheet({super.key, required this.profile});

  static Future<void> show(BuildContext context, PublisherProfile profile) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PublisherProfileSheet(profile: profile),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 36, height: 4,
            decoration: BoxDecoration(color: AppTheme.dividerColor, borderRadius: BorderRadius.circular(2)),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Profile header
                  Row(
                    children: [
                      Container(
                        width: 64, height: 64,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppTheme.accentColor.withValues(alpha: 0.8), AppTheme.accentColor],
                            begin: Alignment.topLeft, end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(profile.avatarInitials,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black)),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Text(profile.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            if (profile.isVerified) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.verified, size: 18, color: AppTheme.accentColor),
                            ],
                          ]),
                          Text(profile.handle, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondaryColor)),
                          const SizedBox(height: 4),
                          Text(
                            'Member since ${profile.memberSince.year}',
                            style: const TextStyle(fontSize: 11, color: AppTheme.textTertiaryColor),
                          ),
                        ]),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Stats row
                  Row(
                    children: [
                      _statBox(_formatNumber(profile.totalSubscribers), 'Subscribers'),
                      const SizedBox(width: 10),
                      _statBox('${profile.strategyCount}', 'Strategies'),
                      const SizedBox(width: 10),
                      _statBox('${profile.averageRating.toStringAsFixed(1)} ★', 'Avg Rating'),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Follow button
                  Consumer<UserProfileService>(
                    builder: (context, userProfile, _) {
                      final isFollowing = userProfile.isFollowing(profile.id);
                      return GestureDetector(
                        onTap: () async {
                          HapticFeedback.lightImpact();
                          if (isFollowing) {
                            await userProfile.unfollow(profile.id);
                          } else {
                            await userProfile.follow(profile.id);
                          }
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: isFollowing ? AppTheme.cardColor : AppTheme.accentColor,
                            borderRadius: BorderRadius.circular(10),
                            border: isFollowing
                                ? Border.all(color: AppTheme.dividerColor)
                                : null,
                          ),
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(
                              isFollowing ? Icons.person_remove_outlined : Icons.person_add_outlined,
                              size: 16,
                              color: isFollowing ? AppTheme.textSecondaryColor : Colors.black,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isFollowing ? 'Following' : 'Follow',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isFollowing ? AppTheme.textSecondaryColor : Colors.black,
                              ),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 20),

                  // Bio
                  const Text('About', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondaryColor)),
                  const SizedBox(height: 8),
                  Text(profile.bio, style: const TextStyle(fontSize: 14, color: AppTheme.textSecondaryColor, height: 1.6)),

                  const SizedBox(height: 24),
                  const Divider(color: AppTheme.dividerColor),
                  const SizedBox(height: 16),

                  Text('Strategies by ${profile.name}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),

                  ...profile.strategies.map((s) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: StrategyCard(
                      strategy: s,
                      onTap: () => StrategyDetailSheet.show(context, s),
                    ),
                  )),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statBox(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: AppTheme.cardColor, borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondaryColor)),
        ]),
      ),
    );
  }

  String _formatNumber(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return n.toString();
  }
}
