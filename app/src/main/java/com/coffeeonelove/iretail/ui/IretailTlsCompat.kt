package com.coffeeonelove.iretail.ui

import android.content.Context
import android.os.Build
import android.util.Log
import java.net.URL
import java.security.KeyStore
import java.security.MessageDigest
import java.security.cert.CertificateException
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509TrustManager

object IretailTlsCompat {
    private const val LEGACY_HOST = "my.i-retail.com"
    private const val ROOT_ASSET = "certs/isrgrootx1.pem"
    private const val EXPECTED_ROOT_SHA256 =
        "96bcec06264976f37460779acf28c5a7cfe8a3c0aae11a8ffcee05c0bddf08c6"

    fun applyIfNeeded(context: Context, url: URL, connection: HttpsURLConnection) {
        if (Build.VERSION.SDK_INT > Build.VERSION_CODES.M) return
        if (!url.host.equals(LEGACY_HOST, ignoreCase = true)) return

        val systemTrust = trustManager(null)
        val extraTrust = trustManager(extraRootStore(context.applicationContext))
        val combined = object : X509TrustManager {
            override fun getAcceptedIssuers(): Array<X509Certificate> =
                systemTrust.acceptedIssuers + extraTrust.acceptedIssuers

            override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) {
                systemTrust.checkClientTrusted(chain, authType)
            }

            override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {
                try {
                    systemTrust.checkServerTrusted(chain, authType)
                    Log.i("IretailTlsCompat", "SYSTEM_TRUST_OK host=${url.host}")
                    return
                } catch (_: CertificateException) {
                    extraTrust.checkServerTrusted(chain, authType)
                    Log.i(
                        "IretailTlsCompat",
                        "SYSTEM_TRUST_FAIL_EXTRA_ROOT_OK host=${url.host} root=ISRG_ROOT_X1"
                    )
                }
            }
        }

        val sslContext = SSLContext.getInstance("TLS")
        sslContext.init(null, arrayOf<TrustManager>(combined), null)
        connection.sslSocketFactory = sslContext.socketFactory
        Log.i(
            "IretailTlsCompat",
            "LEGACY_ROOT_APPLIED host=${url.host} api=${Build.VERSION.SDK_INT} root=ISRG_ROOT_X1"
        )
    }

    private fun extraRootStore(context: Context): KeyStore {
        val certificate = context.assets.open(ROOT_ASSET).use { input ->
            CertificateFactory.getInstance("X.509").generateCertificate(input) as X509Certificate
        }
        val actualFingerprint = sha256(certificate.encoded)
        if (!actualFingerprint.equals(EXPECTED_ROOT_SHA256, ignoreCase = true)) {
            throw CertificateException("Bundled ISRG Root X1 fingerprint mismatch")
        }

        val keyStore = KeyStore.getInstance(KeyStore.getDefaultType())
        keyStore.load(null, null)
        keyStore.setCertificateEntry("isrg-root-x1", certificate)
        return keyStore
    }

    private fun trustManager(keyStore: KeyStore?): X509TrustManager {
        val factory = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm())
        factory.init(keyStore)
        return factory.trustManagers
            .filterIsInstance<X509TrustManager>()
            .firstOrNull()
            ?: throw CertificateException("X509TrustManager unavailable")
    }

    private fun sha256(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256")
            .digest(bytes)
            .joinToString("") { "%02x".format(it) }
}
