// build.sbt

name := "EAGLCOIN"

version := "0.1"

scalaVersion := "2.12.15"

lazy val root = (project in file("."))
  .enablePlugins(sbtassembly.AssemblyPlugin) // only if you plan to build a fat JAR
  .settings(
    resolvers ++= Seq(
      "Typesafe Releases" at "https://repo.typesafe.com/typesafe/releases/",
      Resolver.sonatypeOssRepos("snapshots"),
      "Ergo Maven" at "https://maven.ergoplatform.com/releases"
    ),

    libraryDependencies ++= Seq(
      // Ergo / Scorex core modules
      "org.ergoplatform" %% "ergo" % "5.0.0",               // main Ergo blockchain lib
      "org.ergoplatform" %% "scorex-util" % "3.0.0",        // utility lib
      "org.ergoplatform" %% "scorex-core" % "3.0.0",        // core networking
      "org.ergoplatform" %% "scorex-network" % "3.0.0",     // networking & messages

      // Akka actor dependencies
      "com.typesafe.akka" %% "akka-actor" % "2.6.20",
      "com.typesafe.akka" %% "akka-slf4j" % "2.6.20",

      // JSON & HTTP (if your API routes use spray-json or akka-http)
      "com.typesafe.akka" %% "akka-http" % "10.2.14",
      "com.typesafe.akka" %% "akka-stream" % "2.6.20",
      "com.typesafe.akka" %% "akka-http-spray-json" % "10.2.14"
    )
  )
