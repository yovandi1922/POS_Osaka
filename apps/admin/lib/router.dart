// apps/admin/lib/router.dart
// Proteksi route: belum login → /login; profil sedang dimuat → /splash; admin/owner → halaman dashboard.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'pages/chat_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/expenses_page.dart';
import 'pages/ingredients_page.dart';
import 'pages/login_page.dart';
import 'pages/menu_page.dart';
import 'pages/predictions_page.dart';
import 'pages/reports_page.dart';
import 'pages/transactions_page.dart';
import 'pages/users_page.dart';
import 'state/admin_session.dart';
import 'widgets/shell.dart';

GoRouter buildRouter(AdminSession session) {
  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: session,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      if (!session.ready || session.profileLoading) return loc == '/splash' ? null : '/splash';
      if (!session.signedIn) return loc == '/login' ? null : '/login';
      if (loc == '/login' || loc == '/splash') return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const Scaffold(body: Center(child: CircularProgressIndicator()))),
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      ShellRoute(
        builder: (context, state, child) => AdminShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/dashboard', builder: (_, _) => const DashboardPage()),
          GoRoute(path: '/chat', builder: (_, _) => const ChatPage()),
          GoRoute(path: '/transactions', builder: (_, _) => const TransactionsPage()),
          GoRoute(path: '/menu', builder: (_, _) => const MenuPage()),
          GoRoute(path: '/ingredients', builder: (_, _) => const IngredientsPage()),
          GoRoute(path: '/expenses', builder: (_, _) => const ExpensesPage()),
          GoRoute(path: '/reports', builder: (_, _) => const ReportsPage()),
          GoRoute(path: '/predictions', builder: (_, _) => const PredictionsPage()),
          GoRoute(path: '/users', builder: (_, _) => const UsersPage()),
        ],
      ),
    ],
  );
}
