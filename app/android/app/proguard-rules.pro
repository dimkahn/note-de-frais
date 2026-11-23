# Règles R8 de l'application (build release, minification active).

# google_mlkit_text_recognition référence les options de reconnaissance de toutes les écritures,
# mais seul le modèle latin est embarqué : les classes chinoises, devanagari, japonaises et
# coréennes sont absentes et ne sont jamais utilisées à l'exécution.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
