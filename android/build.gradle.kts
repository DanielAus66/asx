allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Force ALL projects including plugins to use Java 17
subprojects {
    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = "17"
        targetCompatibility = "17"
    }
}

rootProject.buildDir = file("../build")

subprojects {
    project.buildDir = file("${rootProject.buildDir}/${project.name}")
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.buildDir)
}
