import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';

class RegisterScreen extends StatefulWidget {
	const RegisterScreen({super.key});

	@override
	_RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
	final _formKey = GlobalKey<FormState>();
	final _emailController = TextEditingController();
	final _passwordController = TextEditingController();
	final _confirmPasswordController = TextEditingController();

	Future<void> _register() async {
		if (_formKey.currentState!.validate()) {
			try {
				final authService = Provider.of<AuthService>(context, listen: false);
				await authService.signUpWithEmail(
					_emailController.text,
					_passwordController.text,
				);
				if (mounted) {
					Navigator.of(context).pop();
				}
			} catch (e) {
				if (mounted) {
					ScaffoldMessenger.of(context).showSnackBar(
						SnackBar(content: Text(e.toString())),
					);
				}
			}
		}
	}

	@override
	Widget build(BuildContext context) {
		final authService = Provider.of<AuthService>(context, listen: false);

		return Scaffold(
			body: SafeArea(
				child: Column(
					children: [
						// Top section with background image
						Expanded(
							flex: 4,
							child: Stack(
								children: [
									Positioned.fill(
										child: Image.asset(
											'lib/assets/images/auth_background.jpg',
											fit: BoxFit.cover,
										),
									),
									Column(
										children: [
											// Branding at top
											Expanded(
												flex: 2,
												child: Center(
													child: Padding(
														padding: const EdgeInsets.only(top: 40),
														child: Column(
															mainAxisSize: MainAxisSize.min,
															children: [
																Image.asset(
																	'lib/assets/images/Plendy_logo_transparent_without_subtext.png',
																	height: 150,
																	fit: BoxFit.contain,
																),
																const SizedBox(height: 4),
																const Text(
																	'DISCOVER. PLAN. EXPERIENCE.',
																	style: TextStyle(
																		fontSize: 14,
																		fontWeight: FontWeight.w600,
																		letterSpacing: 1.2,
																		color: Colors.white,
																	),
																),
															],
														),
													),
												),
											),
											// Form at bottom
											Container(
												padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
												child: Form(
													key: _formKey,
													child: Column(
														crossAxisAlignment: CrossAxisAlignment.stretch,
														children: [
															TextFormField(
																controller: _emailController,
																style: const TextStyle(color: Colors.black87),
																decoration: InputDecoration(
																	hintText: 'Email',
																	floatingLabelBehavior: FloatingLabelBehavior.never,
																	filled: true,
																	fillColor: Colors.white.withOpacity(0.6),
																	border: OutlineInputBorder(
																		borderRadius: BorderRadius.circular(12),
																		borderSide: BorderSide.none,
																	),
																	contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
																),
																validator: (value) {
																	if (value == null || value.isEmpty) {
																		return 'Please enter your email';
																	}
																	if (!RegExp(r"^\S+@\S+\.\S+$").hasMatch(value)) {
																		return 'Please enter a valid email address';
																	}
																	return null;
																},
															),
															const SizedBox(height: 16),
															TextFormField(
																controller: _passwordController,
																style: const TextStyle(color: Colors.black87),
																decoration: InputDecoration(
																	hintText: 'Password',
																	floatingLabelBehavior: FloatingLabelBehavior.never,
																	filled: true,
																	fillColor: Colors.white.withOpacity(0.6),
																	border: OutlineInputBorder(
																		borderRadius: BorderRadius.circular(12),
																		borderSide: BorderSide.none,
																	),
																	contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
																),
																obscureText: true,
																validator: (value) {
																	if (value == null || value.isEmpty) {
																		return 'Please enter your password';
																	}
																	if (value.length < 6) {
																		return 'Password must be at least 6 characters';
																	}
																	return null;
																},
															),
															const SizedBox(height: 16),
															TextFormField(
																controller: _confirmPasswordController,
																style: const TextStyle(color: Colors.black87),
																decoration: InputDecoration(
																	hintText: 'Confirm Password',
																	floatingLabelBehavior: FloatingLabelBehavior.never,
																	filled: true,
																	fillColor: Colors.white.withOpacity(0.6),
																	border: OutlineInputBorder(
																		borderRadius: BorderRadius.circular(12),
																		borderSide: BorderSide.none,
																	),
																	contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
																),
																obscureText: true,
																validator: (value) {
																	if (value == null || value.isEmpty) {
																		return 'Please confirm your password';
																	}
																	if (value != _passwordController.text) {
																		return 'Passwords do not match';
																	}
																	return null;
																},
															),
															const SizedBox(height: 24),
															Center(
																child: SizedBox(
																	width: 180,
																	child: ElevatedButton(
																		onPressed: _register,
																		style: ElevatedButton.styleFrom(
																			backgroundColor: Colors.black,
																			foregroundColor: Colors.white,
																			padding: const EdgeInsets.symmetric(vertical: 16),
																			shape: const StadiumBorder(),
																		),
																		child: const Text(
																			'Create Account',
																			style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
																		),
																	),
																),
															),
															const SizedBox(height: 40),
														],
													),
												),
											),
										],
									),
								],
							),
						),

						// Bottom section on plain background  
						Expanded(
							flex: 1,
							child: Padding(
								padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
								child: Column(
									mainAxisAlignment: MainAxisAlignment.center,
									children: [
										Row(
											children: [
												Expanded(child: Divider(color: Colors.grey[400])),
												const Padding(
													padding: EdgeInsets.symmetric(horizontal: 16),
													child: Text('Or Sign Up with', style: TextStyle(color: Colors.black87, fontSize: 14)),
												),
												Expanded(child: Divider(color: Colors.grey[400])),
											],
										),
										const SizedBox(height: 12),
										Center(
											child: InkWell(
												onTap: () async {
													try {
														await authService.signInWithGoogle();
														if (mounted) {
															Navigator.of(context).pop();
														}
													} catch (e) {
														if (mounted) {
															ScaffoldMessenger.of(context).showSnackBar(
																SnackBar(content: Text(e.toString())),
															);
														}
													}
												},
												child: const Padding(
													padding: EdgeInsets.symmetric(horizontal: 20),
													child: Icon(FontAwesomeIcons.google, color: Color(0xFFD40000), size: 44),
												),
											),
										),
										const SizedBox(height: 12),
										Row(
											mainAxisAlignment: MainAxisAlignment.center,
											children: [
												Text("Already have an account? ", style: TextStyle(color: Colors.black87, fontSize: 15)),
												GestureDetector(
													onTap: () {
														Navigator.pop(context);
													},
													child: const Text(
														'Sign In',
														style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700, decoration: TextDecoration.underline),
													),
												),
											],
										),
									],
								),
							),
						),
					],
				),
			),
		);
	}
}