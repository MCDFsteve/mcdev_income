package com.aimessoft.consmelt

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.GeneralSecurityException
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    val channel = MethodChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      "mcdev_income/secure_storage",
    )
    channel.setMethodCallHandler { call, result ->
      val key = call.argument<String>("key")
      if (key.isNullOrEmpty()) {
        result.error("invalid_args", "缺少安全存储键名", null)
        return@setMethodCallHandler
      }
      try {
        when (call.method) {
          "read" -> result.success(readSecret(key))
          "write" -> {
            val value = call.argument<String>("value")
            if (value == null) {
              result.error("invalid_args", "缺少安全存储内容", null)
            } else {
              writeSecret(key, value)
              result.success(null)
            }
          }
          "delete" -> {
            deleteSecret(key)
            result.success(null)
          }
          else -> result.notImplemented()
        }
      } catch (e: Exception) {
        result.error("secure_storage_error", e.message, null)
      }
    }
  }

  private fun securePrefs() =
    applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

  private fun getOrCreateKey(): SecretKey {
    val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
    val existing = keyStore.getKey(KEY_ALIAS, null) as? SecretKey
    if (existing != null) return existing
    val generator = KeyGenerator.getInstance(
      KeyProperties.KEY_ALGORITHM_AES,
      ANDROID_KEYSTORE,
    )
    val spec = KeyGenParameterSpec.Builder(
      KEY_ALIAS,
      KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
    )
      .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
      .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
      .setKeySize(256)
      .build()
    generator.init(spec)
    return generator.generateKey()
  }

  private fun writeSecret(key: String, value: String) {
    val cipher = Cipher.getInstance(TRANSFORMATION)
    cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
    val iv = cipher.iv
    val ciphertext = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
    val payload = ByteArray(1 + iv.size + ciphertext.size)
    payload[0] = iv.size.toByte()
    System.arraycopy(iv, 0, payload, 1, iv.size)
    System.arraycopy(ciphertext, 0, payload, 1 + iv.size, ciphertext.size)
    val encoded = Base64.encodeToString(payload, Base64.NO_WRAP)
    securePrefs().edit().putString(key, encoded).apply()
  }

  private fun readSecret(key: String): String? {
    val encoded = securePrefs().getString(key, null) ?: return null
    return try {
      val payload = Base64.decode(encoded, Base64.NO_WRAP)
      if (payload.isEmpty()) return null
      val ivLen = payload[0].toInt() and 0xFF
      if (ivLen <= 0 || payload.size <= 1 + ivLen) {
        deleteSecret(key)
        return null
      }
      val iv = payload.copyOfRange(1, 1 + ivLen)
      val ciphertext = payload.copyOfRange(1 + ivLen, payload.size)
      val cipher = Cipher.getInstance(TRANSFORMATION)
      cipher.init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(128, iv))
      String(cipher.doFinal(ciphertext), Charsets.UTF_8)
    } catch (_: GeneralSecurityException) {
      deleteSecret(key)
      null
    } catch (_: IllegalArgumentException) {
      deleteSecret(key)
      null
    }
  }

  private fun deleteSecret(key: String) {
    securePrefs().edit().remove(key).apply()
  }

  companion object {
    private const val ANDROID_KEYSTORE = "AndroidKeyStore"
    private const val KEY_ALIAS = "com.aimessoft.consmelt.session_key"
    private const val PREFS_NAME = "mcdev_secure_storage"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
  }
}
