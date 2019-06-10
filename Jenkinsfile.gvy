pipeline {
    agent any
    parameters {
        string(name:'GITHUB_USER', defaultValue: 'CCS_HIOS_jenkins_rw', description: 'github service account user')
        string(name:'BRANCH', defaultValue: 'dev', description:"Choose which branch to build")
    }
    options { skipDefaultCheckout() }
    environment {
        GITHUB_PASSWORD = credentials('864d7a41-0618-4d0f-b0af-d6c8a0701d03')
        FORTIFY_HOME = '/var/fortify/Fortify/bin/'
        S3_BUCKET = 's3://hios-devops/Fortify/'
        NEXUS_URL = sh(script: 'ansible -i /var/lib/jenkins/devops_hosts nexus --list-hosts | sed -n 2p',returnStdout: true).trim()
        NEXUS_USER = credentials('eeba7924-4975-445c-8495-2c59b4628b6e')
        NEXUS_PW = credentials('8492e112-4ef8-453f-af98-dcf319201ab6')
    }
    stages {
        stage('Clean Workspace') {
            steps {
                echo 'Cleaning Workspace....'
                sh 'rm -rf *'
            }
        }
        stage('Checkout HIOS-BUILD') {
            steps {
                echo 'Checkout SCM....'
                sh 'mkdir stagedir'
                dir('stagedir') {
                git branch: 'buildTest', credentialsId: 'e4a25c3e-1eda-4b9b-b1ea-36748dba3d42', url: 'https://github.cms.gov/HIOS/HIOS-BUILD.git'
                }
            }
        }
        stage('Checkout for Module') {
            steps {
                echo 'Checkout SCM....'
                git branch: "${BRANCH}", credentialsId: "e4a25c3e-1eda-4b9b-b1ea-36748dba3d42", url: "https://github.cms.gov/HIOS/${JOB_NAME}.git"
                sh "sed -i 's/repo/${JOB_NAME}/g' stagedir/sonar-project.properties"
                sh 'cp stagedir/sonar-project.properties .'
            }
        }
        stage('Sonar Scan') {
            steps {
                echo 'Sonar Scanning....'
                withSonarQubeEnv('Sonar') {
                sh "/var/lib/jenkins/tools/hudson.plugins.sonar.SonarRunnerInstallation/Sonar/bin/sonar-scanner scan"
                }
            }
        }
        stage('Run Build') {
            steps {
                sh "cp stagedir/build.sh . && chmod 755 ${WORKSPACE}/build.sh && ${WORKSPACE}/build.sh ${BRANCH} ${GITHUB_USER} ${GITHUB_PASSWORD} ${JOB_NAME} ${BUILD_ID}"
            }
        }
//        stage('Fortify Scan') {
//            agent {
//                label 'Fortify'
//            }
//            steps {
//                echo 'Checkout SCM....'
//                git branch: '$BRANCH', credentialsId: 'e4a25c3e-1eda-4b9b-b1ea-36748dba3d42', url: 'https://github.cms.gov/HIOS/$JOB_NAME.git'
//                sh"""
//                    ${FORTIFY_HOME}sourceanalyzer -b ${BUILD_ID} -clean
//                    ${FORTIFY_HOME}sourceanalyzer -b ${BUILD_ID} ${WORKSPACE}
//                    ${FORTIFY_HOME}sourceanalyzer -b ${BUILD_ID} -scan -64 -verbose -Xmx6G -format fpr -f ${WORKSPACE}/${JOB_NAME}.fpr
//                    ${FORTIFY_HOME}ReportGenerator -template "DeveloperWorkbook.xml" -format pdf -f ${WORKSPACE}/${JOB_NAME}.pdf -source  ${WORKSPACE}/${JOB_NAME}.fpr
//                    aws s3 cp ${WORKSPACE}/${JOB_NAME}.pdf ${S3_BUCKET}${JOB_NAME}.pdf
//                """
//            }
//        }
        stage('Post to Nexus') {
            steps {
                sh "cp ${WORKSPACE}/release/*.zip ${WORKSPACE}/release/${BUILD_ID}.zip"
                sh "curl --fail -u ${NEXUS_USER}:${NEXUS_PW} --upload-file ${WORKSPACE}/release/${BUILD_ID}.zip ${NEXUS_URL}:8081/repository/${JOB_NAME}/"
            }
        }

    }
}
