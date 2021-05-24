import * as core from '@actions/core'
import * as crypto from 'crypto'

const run = () => {
  core.startGroup('Configuring git env variables')

  const gitRef = core.getInput('gitRef') || process.env['GITHUB_REF']!
  console.info(`gitRef: ${gitRef}`)

  try {
    const branch = gitRef.startsWith('refs/heads/') ? gitRef.substring('refs/heads/'.length) : gitRef
    console.info(`branch: ${branch}`)

    core.exportVariable('BRANCH_NAME', branch)

    const envName = toShortHash(branch)
    console.info(`envName: ${envName}`)

    core.exportVariable('ENV_NAME', envName)
  } catch (err) {
    console.error(err)
    core.setFailed('An error occurred while determining the git env')
  } finally {
    core.endGroup()
  }
}

const toShortHash = (s: string): string => {
  return crypto.createHash('sha1').update(s).digest('hex').substring(0, 6)
}

run()