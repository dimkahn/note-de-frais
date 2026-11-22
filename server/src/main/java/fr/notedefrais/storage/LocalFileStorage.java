package fr.notedefrais.storage;

import java.io.IOException;
import java.nio.file.FileAlreadyExistsException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.nio.file.StandardOpenOption;
import java.util.Locale;
import java.util.UUID;

/**
 * Arborescence : {@code <racine>/<id>/original.<ext>} (lecture seule après écriture)
 * et {@code <racine>/<id>/processed.jpg}.
 */
public final class LocalFileStorage implements FileStorage {

    static final String PROCESSED = "processed.jpg";

    private final Path root;

    public LocalFileStorage(Path root) {
        this.root = root.toAbsolutePath().normalize();
    }

    @Override
    public String saveOriginal(UUID expenseId, byte[] content, String extension) {
        String name = "original." + sanitizeExtension(extension);
        Path target = resolve(expenseId, name);
        try {
            Files.createDirectories(target.getParent());
            Files.write(target, content, StandardOpenOption.CREATE_NEW, StandardOpenOption.WRITE);
            target.toFile().setReadOnly();
            return name;
        } catch (FileAlreadyExistsException e) {
            throw new OriginalAlreadyExistsException(expenseId);
        } catch (IOException e) {
            throw new StorageException("Impossible d'enregistrer l'original " + expenseId, e);
        }
    }

    @Override
    public String saveProcessed(UUID expenseId, byte[] jpeg) {
        Path target = resolve(expenseId, PROCESSED);
        try {
            Files.createDirectories(target.getParent());
            Path tmp = Files.createTempFile(target.getParent(), "processed", ".tmp");
            Files.write(tmp, jpeg);
            Files.move(tmp, target, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
            return PROCESSED;
        } catch (IOException e) {
            throw new StorageException("Impossible d'enregistrer l'image traitée " + expenseId, e);
        }
    }

    @Override
    public byte[] read(UUID expenseId, String fileName) {
        try {
            return Files.readAllBytes(resolve(expenseId, fileName));
        } catch (IOException e) {
            throw new StorageException("Fichier introuvable : " + expenseId + "/" + fileName, e);
        }
    }

    private Path resolve(UUID expenseId, String fileName) {
        Path dir = root.resolve(expenseId.toString());
        Path file = dir.resolve(fileName).normalize();
        if (!file.getParent().equals(dir)) {
            throw new IllegalArgumentException("Nom de fichier invalide : " + fileName);
        }
        return file;
    }

    private static String sanitizeExtension(String extension) {
        String ext = extension == null ? "" : extension.toLowerCase(Locale.ROOT).replaceAll("[^a-z0-9]", "");
        return ext.isEmpty() ? "bin" : ext;
    }
}
