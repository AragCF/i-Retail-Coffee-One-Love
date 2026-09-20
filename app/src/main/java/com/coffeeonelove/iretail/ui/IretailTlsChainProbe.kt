package com.coffeeonelove.iretail.ui

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.security.KeyStore
import java.security.MessageDigest
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.TrustManagerFactory
import javax.net.ssl.X509TrustManager
import java.net.URL

object IretailTlsChainProbe {
    fun runAsync(context: Context) {
        Thread {
            try {
                probe(context)
            } catch (e: Exception) {
                Log.e("IretailTls", "PROBE_ERROR cause=${throwableClasses(e)}")
            }
        }.start()
    }

    private fun probe(context: Context) {
        val configText = context.assets.open("content/iretail-api.json")
            .bufferedReader(Charsets.UTF_8)
            .use { it.readText() }
        val baseUrl = JSONObject(configText).optString("base_url", "https://my.i-retail.com/api/")
        val url = URL(baseUrl)

        val tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm())
        tmf.init(null as KeyStore?)
        val systemTrust = tmf.trustManagers
            .filterIsInstance<X509TrustManager>()
            .firstOrNull()
            ?: throw IllegalStateException("No system X509TrustManager")

        val loggingTrust = object : X509TrustManager {
            override fun getAcceptedIssuers(): Array<X509Certificate> = systemTrust.acceptedIssuers

            override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) {
                systemTrust.checkClientTrusted(chain, authType)
            }

            override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {
                Log.i("IretailTls", "CHAIN host=${url.host} size=${chain.size} authType=${safeToken(authType)}")
                chain.forEachIndexed { index, cert ->
                    Log.i(
                        "IretailTls",
                        "CERT index=$index subject=${safePrincipal(cert.subjectX500Principal.name)} " +
                            "issuer=${safePrincipal(cert.issuerX500Principal.name)} " +
                            "notBefore=${cert.notBefore.time} notAfter=${cert.notAfter.time} " +
                            "sigAlg=${safeToken(cert.sigAlgName)} sha256=${sha256(cert.encoded)}"
                    )
                }
                try {
                    systemTrust.checkServerTrusted(chain, authType)
                    Log.i("IretailTls", "SYSTEM_TRUST=OK")
                } catch (e: CertificateException) {
                    Log.e("IretailTls", "SYSTEM_TRUST=FAIL cause=${throwableClasses(e)}")
                    throw e
                }
            }
        }

        val sslContext = SSLContext.getInstance("TLS")
        sslContext.init(null, arrayOf<TrustManager>(loggingTrust), null)

        val conn = (url.openConnection() as HttpsURLConnection).apply {
            sslSocketFactory = sslContext.socketFactory
            requestMethod = "HEAD"
            connectTimeout = 15000
            readTimeout = 15000
            instanceFollowRedirects = false
            useCaches = false
        }

        try {
            conn.connect()
            Log.i(
                "IretailTls",
                "PROBE_CONNECTED host=${url.host} response=${conn.responseCode} cipher=${safeToken(conn.cipherSuite)}"
            )
        } catch (e: Exception) {
            Log.e("IretailTls", "PROBE_FAILED host=${url.host} cause=${throwableClasses(e)}")
        } finally {
            conn.disconnect()
        }
    }

    private fun throwableClasses(error: Throwable): String {
        val result = mutableListOf<String>()
        var current: Throwable? = error
        var depth = 0
        while (current != null && depth < 8) {
            val name = current.javaClass.simpleName.take(64).ifBlank { "Throwable" }
            if (result.lastOrNull() != name) result.add(name)
            current = current.cause
            depth++
        }
        return result.joinToString(">").take(320).ifBlank { "unknown" }
    }

    private fun safePrincipal(value: String): String =
        value.replace(Regex("[\\r\\n\\t]"), " ").take(500)

    private fun safeToken(value: String): String =
        value.replace(Regex("[^A-Za-z0-9_.:/+-]"), "_").take(120)

    private fun sha256(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256")
            .digest(bytes)
            .joinToString("") { "%02x".format(it) }
}
