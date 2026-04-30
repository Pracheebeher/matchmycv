import 'package:flutter/material.dart';
import '../models/resume_model.dart';
import '../l10n/app_localizations.dart';
import '../widgets/uniform_app_bar.dart';

class PersonalInfoPage extends StatefulWidget {
  final ResumeData data;

  PersonalInfoPage({required this.data});

  @override
  _PersonalInfoPageState createState() => _PersonalInfoPageState();
}

class _PersonalInfoPageState extends State<PersonalInfoPage> {

  late TextEditingController name;
  late TextEditingController email;
  late TextEditingController phone;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.data.name);
    email = TextEditingController(text: widget.data.email);
    phone = TextEditingController(text: widget.data.phone);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: UniformAppBar.material(
        AppLocalizations.of(context).personalInfoTitle,
      ),

      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [

            TextField(
              controller: name,
              decoration: InputDecoration(labelText: "Name"),
            ),

            TextField(
              controller: email,
              decoration: InputDecoration(labelText: "Email"),
            ),

            TextField(
              controller: phone,
              decoration: InputDecoration(labelText: "Phone"),
            ),
            TextField(
              controller: TextEditingController(
                text: widget.data.skills.join(", "),
              ),
              decoration: InputDecoration(labelText: "Skills"),
            )
            SizedBox(height: 20),

            ElevatedButton(
              onPressed: () {
                widget.data.name = name.text;
                widget.data.email = email.text;
                widget.data.phone = phone.text;

                Navigator.pop(context);
              },
              child: Text("Save"),
            )
          ],
        ),
      ),
    );
  }
}