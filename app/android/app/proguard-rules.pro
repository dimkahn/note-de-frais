# Règles R8 de l'application (build release, minification active).

# google_mlkit_text_recognition référence les options de reconnaissance de toutes les écritures,
# mais seul le modèle latin est embarqué : les classes chinoises, devanagari, japonaises et
# coréennes sont absentes et ne sont jamais utilisées à l'exécution.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# ML Kit (reconnaissance de texte, scanner de documents) enregistre ses composants et charge ses
# implémentations par réflexion : renommées ou retirées par R8, l'appel natif échoue
# (NullPointerException dans processImage, scanner « indisponible »). On les garde telles quelles,
# ainsi que les plugins Flutter qui les appellent.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-keep class com.google.android.gms.mlkit_** { *; }
-keep class com.google_mlkit_commons.** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }
-keep class com.google_mlkit_document_scanner.** { *; }
