import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';

class UploadPotholePage extends StatefulWidget {
  const UploadPotholePage({super.key});

  @override
  State<UploadPotholePage> createState() =>
      _UploadPotholePageState();
}

class _UploadPotholePageState
    extends State<UploadPotholePage> {

  File? image;

  final latitudeController =
      TextEditingController();

  final longitudeController =
      TextEditingController();

  final ImagePicker picker = ImagePicker();

  // ---------------- PICK IMAGE ----------------

  Future<void> pickImage() async {

    final XFile? pickedImage =
        await picker.pickImage(
      source: ImageSource.gallery,
    );

    if (pickedImage != null) {

      setState(() {
        image = File(pickedImage.path);
      });
    }
  }

  // ---------------- GET LOCATION ----------------

  Future<void> getLocation() async {

    bool serviceEnabled =
        await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Please enable Location on your phone",
          ),
        ),
      );

      return;
    }

    LocationPermission permission =
        await Geolocator.checkPermission();

    if (permission ==
        LocationPermission.denied) {

      permission =
          await Geolocator.requestPermission();

      if (permission ==
          LocationPermission.denied) {

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Location permission denied",
            ),
          ),
        );

        return;
      }
    }

    if (permission ==
        LocationPermission.deniedForever) {

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Location permission permanently denied",
          ),
        ),
      );

      return;
    }

    Position position =
        await Geolocator.getCurrentPosition();

    setState(() {

      latitudeController.text =
          position.latitude.toString();

      longitudeController.text =
          position.longitude.toString();
    });
  }

  // ---------------- DISPOSE ----------------

  @override
  void dispose() {

    latitudeController.dispose();
    longitudeController.dispose();

    super.dispose();
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(
        title: const Text(
          "Upload Pot Hole",
        ),
      ),

      body: SingleChildScrollView(

        padding: const EdgeInsets.all(20),

        child: Column(
          children: [

            // IMAGE AREA

            image == null

                ? Container(
                    height: 220,
                    width: double.infinity,

                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.grey,
                      ),
                      borderRadius:
                          BorderRadius.circular(10),
                    ),

                    child: const Center(
                      child: Text(
                        "No Image Selected",
                      ),
                    ),
                  )

                : ClipRRect(
                    borderRadius:
                        BorderRadius.circular(10),

                    child: Image.file(
                      image!,
                      height: 220,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),

            const SizedBox(height: 20),

            // UPLOAD PHOTO

            SizedBox(
              width: double.infinity,

              child: ElevatedButton.icon(

                onPressed: pickImage,

                icon: const Icon(
                  Icons.photo,
                ),

                label: const Text(
                  "Upload Photo",
                ),
              ),
            ),

            const SizedBox(height: 30),

            // LATITUDE

            TextField(

              controller: latitudeController,

              keyboardType:
                  const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),

              decoration:
                  const InputDecoration(

                border:
                    OutlineInputBorder(),

                labelText: "Latitude",

                hintText:
                    "Enter latitude",

                prefixIcon: Icon(
                  Icons.location_on,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // LONGITUDE

            TextField(

              controller:
                  longitudeController,

              keyboardType:
                  const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),

              decoration:
                  const InputDecoration(

                border:
                    OutlineInputBorder(),

                labelText: "Longitude",

                hintText:
                    "Enter longitude",

                prefixIcon: Icon(
                  Icons.location_on,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // GET LOCATION

            SizedBox(
              width: double.infinity,

              child: ElevatedButton.icon(

                onPressed: getLocation,

                icon: const Icon(
                  Icons.my_location,
                ),

                label: const Text(
                  "Get Current Location",
                ),
              ),
            ),

            const SizedBox(height: 30),

            // SUBMIT

            SizedBox(
              width: double.infinity,
              height: 50,

              child: ElevatedButton(

                onPressed: () {

                  if (image == null) {

                    ScaffoldMessenger.of(context)
                        .showSnackBar(
                      const SnackBar(
                        content: Text(
                          "Please select a pothole image",
                        ),
                      ),
                    );

                    return;
                  }

                  if (latitudeController
                      .text
                      .isEmpty ||
                      longitudeController
                          .text
                          .isEmpty) {

                    ScaffoldMessenger.of(context)
                        .showSnackBar(
                      const SnackBar(
                        content: Text(
                          "Please enter latitude and longitude",
                        ),
                      ),
                    );

                    return;
                  }

                  ScaffoldMessenger.of(context)
                      .showSnackBar(
                    const SnackBar(
                      content: Text(
                        "Pot Hole Uploaded",
                      ),
                    ),
                  );
                },

                child: const Text(
                  "Submit",

                  style: TextStyle(
                    fontSize: 18,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}