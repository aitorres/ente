import "dart:developer";

import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/ml/db.dart";
import "package:photos/events/people_changed_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/services/machine_learning/face_ml/feedback/cluster_feedback.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/services/search_service.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/common/date_input.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/components/buttons/button_widget.dart";
import "package:photos/ui/components/models/button_type.dart";
import "package:photos/ui/viewer/file/no_thumbnail_widget.dart";
import "package:photos/ui/viewer/people/person_row_item.dart";
import "package:photos/ui/viewer/search/result/person_face_widget.dart";
import "package:photos/utils/dialog_util.dart";
import "package:photos/utils/toast_util.dart";

class SavePerson extends StatefulWidget {
  final String clusterID;
  final EnteFile? file;
  final bool isEditing;

  const SavePerson(
    this.clusterID, {
    super.key,
    this.file,
    this.isEditing = false,
  });

  @override
  State<SavePerson> createState() => _SavePersonState();
}

class _SavePersonState extends State<SavePerson> {
  bool isKeypadOpen = false;
  String _inputName = "";
  bool userAlreadyAssigned = false;
  late final Logger _logger = Logger("_SavePersonState");

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: isKeypadOpen,
      appBar: AppBar(
        title: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            context.l10n.savePerson,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16.0, left: 16.0, right: 16.0),
        child: Column(
          children: [
            const SizedBox(height: 48),
            SizedBox(
              height: 110,
              width: 110,
              child: ClipPath(
                clipper: ShapeBorderClipper(
                  shape: ContinuousRectangleBorder(
                    borderRadius: BorderRadius.circular(80),
                  ),
                ),
                child: widget.file != null
                    ? PersonFaceWidget(widget.file!,
                        clusterID: widget.clusterID)
                    : const NoThumbnailWidget(
                        addBorder: false,
                      ),
              ),
            ),
            const SizedBox(height: 36),
            TextFormField(
              onChanged: (value) {
                setState(() {
                  _inputName = value;
                });
              },
              decoration: InputDecoration(
                focusedBorder: OutlineInputBorder(
                  borderRadius: const BorderRadius.all(Radius.circular(8.0)),
                  borderSide: BorderSide(
                    color: getEnteColorScheme(context).strokeMuted,
                  ),
                ),
                fillColor: getEnteColorScheme(context).fillFaint,
                filled: true,
                hintText: context.l10n.enterName,
                hintStyle: getEnteTextTheme(context).bodyFaint,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: UnderlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 16),
            DatePickerField(
              hintText: context.l10n.enterDateOfBirth,
              firstDate: DateTime(100),
              lastDate: DateTime.now(),
              isRequired: false,
            ),
            const SizedBox(height: 32),
            ButtonWidget(
              buttonType: ButtonType.primary,
              labelText: context.l10n.save,
              isDisabled: _inputName.isEmpty,
              onTap: () async {
                await addNewPerson(
                  context,
                  text: _inputName,
                  clusterID: widget.clusterID,
                );
              },
            ),
            const SizedBox(height: 32),
            _getPersonItems(),
          ],
        ),
      ),
    );
  }

  Widget _getPersonItems() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 4, 0),
      child: FutureBuilder<List<(PersonEntity, EnteFile)>>(
        future: _getPersonsWithRecentFile(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            log("Error: ${snapshot.error} ${snapshot.stackTrace}}");
            if (kDebugMode) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${snapshot.error}'),
                  Text('${snapshot.stackTrace}'),
                ],
              );
            } else {
              return const SizedBox.shrink();
            }
          } else if (snapshot.hasData) {
            final persons = snapshot.data!;
            final searchResults = _inputName.isNotEmpty
                ? persons
                    .where(
                      (element) => element.$1.data.name
                          .toLowerCase()
                          .contains(_inputName.toLowerCase()),
                    )
                    .toList()
                : persons;
            searchResults.sort(
              (a, b) => a.$1.data.name.compareTo(b.$1.data.name),
            );

            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // left align
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 12),
                    child: Text(
                      context.l10n.orMergeWithExistingPerson,
                      style: getEnteTextTheme(context).largeBold,
                    ),
                  ),

                  SizedBox(
                    height: 160, // Adjust this height based on your needs
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(
                        scrollbars: true,
                      ),
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.only(right: 8),
                        itemCount: searchResults.length,
                        itemBuilder: (context, index) {
                          final person = searchResults[index];
                          return PersonGridItem(
                            person: person.$1,
                            personFile: person.$2,
                            onTap: () async {
                              if (userAlreadyAssigned) {
                                return;
                              }
                              userAlreadyAssigned = true;
                              await MLDataDB.instance.assignClusterToPerson(
                                personID: person.$1.remoteID,
                                clusterID: widget.clusterID,
                              );
                              Bus.instance.fire(PeopleChangedEvent());

                              Navigator.pop(context, person);
                            },
                          );
                        },
                        separatorBuilder: (context, index) {
                          return const SizedBox(width: 6);
                        },
                      ),
                    ),
                  ),
                ]);
          } else {
            return const EnteLoadingWidget();
          }
        },
      ),
    );
  }

  Future<void> addNewPerson(
    BuildContext context, {
    String text = '',
    required String clusterID,
  }) async {
    try {
      if (userAlreadyAssigned) {
        return;
      }
      if (text.trim() == "") {
        return;
      }
      userAlreadyAssigned = true;
      final personEntity =
          await PersonService.instance.addPerson(text, clusterID);
      final bool extraPhotosFound =
          await ClusterFeedbackService.instance.checkAndDoAutomaticMerges(
        personEntity,
        personClusterID: clusterID,
      );
      if (extraPhotosFound) {
        showShortToast(context, S.of(context).extraPhotosFound);
      }
      Bus.instance.fire(PeopleChangedEvent());
      Navigator.pop(context, personEntity);
    } catch (e) {
      _logger.severe("Error adding new person", e);
      userAlreadyAssigned = false;
      await showGenericErrorDialog(context: context, error: e);
    }
  }

  Future<List<(PersonEntity, EnteFile)>> _getPersonsWithRecentFile({
    bool excludeHidden = true,
  }) async {
    final persons = await PersonService.instance.getPersons();
    if (excludeHidden) {
      persons.removeWhere((person) => person.data.isIgnored);
    }
    final List<(PersonEntity, EnteFile)> personAndFileID = [];
    for (final person in persons) {
      final clustersToFiles =
          await SearchService.instance.getClusterFilesForPersonID(
        person.remoteID,
      );
      final files = clustersToFiles.values.expand((e) => e).toList();
      if (files.isEmpty) {
        debugPrint(
          "Person ${kDebugMode ? person.data.name : person.remoteID} has no files",
        );
        continue;
      }
      personAndFileID.add((person, files.first));
    }
    return personAndFileID;
  }
}
