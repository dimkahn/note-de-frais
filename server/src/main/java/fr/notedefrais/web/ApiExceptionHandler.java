package fr.notedefrais.web;

import fr.notedefrais.account.AccountNotFoundException;
import fr.notedefrais.account.EmailAlreadyUsedException;
import fr.notedefrais.account.GoogleAccountRefusedException;
import fr.notedefrais.account.GoogleSignInUnavailableException;
import fr.notedefrais.account.InvalidCredentialsException;
import fr.notedefrais.account.InvalidDeviceKeyException;
import fr.notedefrais.account.InvalidGoogleTokenException;
import fr.notedefrais.account.InvalidPasswordException;
import fr.notedefrais.account.PasswordNotSetException;
import fr.notedefrais.document.DocumentNotFoundException;
import fr.notedefrais.expense.ExpenseNotFoundException;
import fr.notedefrais.account.QuotaExceededException;
import fr.notedefrais.receipt.imaging.InvalidQuadException;
import fr.notedefrais.storage.OriginalAlreadyExistsException;
import fr.notedefrais.storage.StorageException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

/** Traduction unique des erreurs métier en réponses HTTP (RFC 9457). */
@RestControllerAdvice
public class ApiExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(ApiExceptionHandler.class);

    @ExceptionHandler(ExpenseNotFoundException.class)
    ProblemDetail notFound(ExpenseNotFoundException e) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, e.getMessage());
    }

    @ExceptionHandler(DocumentNotFoundException.class)
    ProblemDetail documentNotFound(DocumentNotFoundException e) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, e.getMessage());
    }

    @ExceptionHandler(AccountNotFoundException.class)
    ProblemDetail accountNotFound(AccountNotFoundException e) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, e.getMessage());
    }

    /** Corps exploitable par l'app : {@code code}, {@code usedBytes}, {@code quotaBytes}. */
    @ExceptionHandler(QuotaExceededException.class)
    ProblemDetail quotaExceeded(QuotaExceededException e) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.FORBIDDEN, e.getMessage());
        problem.setProperty("code", "QUOTA_EXCEEDED");
        problem.setProperty("usedBytes", e.usedBytes());
        problem.setProperty("quotaBytes", e.quotaBytes());
        return problem;
    }

    @ExceptionHandler(BadRequestException.class)
    ProblemDetail badRequest(BadRequestException e) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, e.getMessage());
    }

    @ExceptionHandler(InvalidQuadException.class)
    ProblemDetail invalidCorners(InvalidQuadException e) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, e.getMessage());
    }

    @ExceptionHandler(UnsupportedImageTypeException.class)
    ProblemDetail unsupported(UnsupportedImageTypeException e) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.UNSUPPORTED_MEDIA_TYPE, e.getMessage());
    }

    @ExceptionHandler(OriginalAlreadyExistsException.class)
    ProblemDetail conflict(OriginalAlreadyExistsException e) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.CONFLICT, e.getMessage());
    }

    @ExceptionHandler(EmailAlreadyUsedException.class)
    ProblemDetail emailTaken(EmailAlreadyUsedException e) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.CONFLICT, e.getMessage());
    }

    @ExceptionHandler(InvalidPasswordException.class)
    ProblemDetail invalidPassword(InvalidPasswordException e) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, e.getMessage());
    }

    @ExceptionHandler(InvalidCredentialsException.class)
    ProblemDetail invalidCredentials(InvalidCredentialsException e) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.UNAUTHORIZED, e.getMessage());
    }

    @ExceptionHandler(InvalidDeviceKeyException.class)
    ProblemDetail invalidDeviceKey(InvalidDeviceKeyException e) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.UNAUTHORIZED, e.getMessage());
    }

    /** {@code code} permet à l'app de proposer la connexion Google. */
    @ExceptionHandler(PasswordNotSetException.class)
    ProblemDetail passwordNotSet(PasswordNotSetException e) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(HttpStatus.UNAUTHORIZED, e.getMessage());
        problem.setProperty("code", "PASSWORD_NOT_SET");
        return problem;
    }

    @ExceptionHandler(InvalidGoogleTokenException.class)
    ProblemDetail invalidGoogleToken(InvalidGoogleTokenException e) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.UNAUTHORIZED, e.getMessage());
    }

    @ExceptionHandler(GoogleAccountRefusedException.class)
    ProblemDetail googleAccountRefused(GoogleAccountRefusedException e) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.FORBIDDEN, e.getMessage());
    }

    /** Non configurée, ou Google injoignable (cause journalisée, jamais le jeton). */
    @ExceptionHandler(GoogleSignInUnavailableException.class)
    ProblemDetail googleSignInUnavailable(GoogleSignInUnavailableException e) {
        if (e.getCause() != null) log.warn("Vérification Google impossible", e.getCause());
        return ProblemDetail.forStatusAndDetail(HttpStatus.SERVICE_UNAVAILABLE, e.getMessage());
    }

    @ExceptionHandler(StorageException.class)
    ProblemDetail storage(StorageException e) {
        log.error("Erreur de stockage", e);
        return ProblemDetail.forStatusAndDetail(HttpStatus.INTERNAL_SERVER_ERROR, "Erreur de stockage des fichiers");
    }
}
