// init.gradle.kts - 配置 Gradle 使用备用仓库镜像
// 解决 Maven Central 403 错误问题

allprojects {
    buildscript {
        repositories {
            maven { url = uri("https://cache-redirector.jetbrains.com/plugins.gradle.org") }
            maven { url = uri("https://cache-redirector.jetbrains.com/maven.google.com") }
            maven { url = uri("https://cache-redirector.jetbrains.com/repo1.maven.org/maven2") }
            maven { url = uri("https://cache-redirector.jetbrains.com/jcenter.bintray.com") }
            google()
            mavenCentral()
        }
    }

    repositories {
        maven { url = uri("https://cache-redirector.jetbrains.com/plugins.gradle.org") }
        maven { url = uri("https://cache-redirector.jetbrains.com/maven.google.com") }
        maven { url = uri("https://cache-redirector.jetbrains.com/repo1.maven.org/maven2") }
        maven { url = uri("https://cache-redirector.jetbrains.com/jcenter.bintray.com") }
        google()
        mavenCentral()
    }
}

settingsEvaluated { settings ->
    settings.pluginManagement {
        repositories {
            maven { url = uri("https://cache-redirector.jetbrains.com/plugins.gradle.org") }
            maven { url = uri("https://cache-redirector.jetbrains.com/maven.google.com") }
            maven { url = uri("https://cache-redirector.jetbrains.com/repo1.maven.org/maven2") }
            mavenCentral()
            gradlePluginPortal()
        }
    }
}
