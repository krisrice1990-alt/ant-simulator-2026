package com.antsim2026.prototype.antupdater;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;

import androidx.annotation.NonNull;
import androidx.core.content.FileProvider;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

import java.io.File;

/**
 * AntUpdaterPlugin - lets the game install a downloaded APK update.
 *
 * Exposed to GDScript as the "AntUpdater" singleton:
 *   var plugin = Engine.get_singleton("AntUpdater")
 *   plugin.call("installApk", "/data/data/.../files/update.apk")
 *
 * Android 8+ requires the user to allow "install unknown apps" for this app;
 * use canRequestInstallPermission() / openInstallPermissionSettings() for that.
 */
public class AntUpdaterPlugin extends GodotPlugin {

    private static final String FILE_PROVIDER_SUFFIX = ".antupdater.fileprovider";

    public AntUpdaterPlugin(Godot godot) {
        super(godot);
    }

    @NonNull
    @Override
    public String getPluginName() {
        return "AntUpdater";
    }

    /**
     * Launches the system package installer for the APK at absolutePath.
     * The file is shared through FileProvider (declared in the plugin manifest).
     */
    @UsedByGodot
    public void installApk(String absolutePath) {
        Activity activity = getActivity();
        if (activity == null || absolutePath == null || absolutePath.isEmpty()) {
            return;
        }
        File apkFile = new File(absolutePath);
        if (!apkFile.exists()) {
            return;
        }
        String authority = activity.getPackageName() + FILE_PROVIDER_SUFFIX;
        Uri apkUri = FileProvider.getUriForFile(activity, authority, apkFile);
        Intent intent = new Intent(Intent.ACTION_VIEW);
        intent.setDataAndType(apkUri, "application/vnd.android.package-archive");
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        activity.startActivity(intent);
    }

    /**
     * Returns true when the app is allowed to install unknown APKs
     * (always true below Android 8).
     */
    @UsedByGodot
    public boolean canRequestInstallPermission() {
        Activity activity = getActivity();
        if (activity == null) {
            return false;
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            return activity.getPackageManager().canRequestPackageInstalls();
        }
        return true;
    }

    /**
     * Opens this app's "install unknown apps" settings page so the user can
     * grant the permission, then come back and tap install again.
     */
    @UsedByGodot
    public void openInstallPermissionSettings() {
        Activity activity = getActivity();
        if (activity == null) {
            return;
        }
        Intent intent;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            intent = new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:" + activity.getPackageName()));
        } else {
            intent = new Intent(Settings.ACTION_SECURITY_SETTINGS);
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        activity.startActivity(intent);
    }
}
