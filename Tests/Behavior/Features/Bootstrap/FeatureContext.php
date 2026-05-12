<?php

/*
 * This file is part of the Sandstorm.NodeTypes.Folder package.
 */

use Behat\Behat\Context\Context as BehatContext;
use Neos\Behat\FlowBootstrapTrait;
use Neos\ContentRepository\Core\ContentRepository;
use Neos\ContentRepository\Core\Factory\ContentRepositoryServiceFactoryInterface;
use Neos\ContentRepository\Core\Factory\ContentRepositoryServiceInterface;
use Neos\ContentRepository\Core\SharedModel\ContentRepository\ContentRepositoryId;
use Neos\ContentRepository\TestSuite\Behavior\Features\Bootstrap\CRBehavioralTestsSubjectProvider;
use Neos\ContentRepository\TestSuite\Behavior\Features\Bootstrap\CRTestSuiteTrait;
use Neos\ContentRepository\TestSuite\Behavior\Features\Bootstrap\MigrationsTrait;
use Neos\ContentRepository\TestSuite\Fakes\FakeContentDimensionSourceFactory;
use Neos\ContentRepository\TestSuite\Fakes\FakeNodeTypeManagerFactory;
use Neos\ContentRepositoryRegistry\ContentRepositoryRegistry;
use Neos\Flow\Persistence\PersistenceManagerInterface;
use Neos\Flow\Utility\Environment;

class FeatureContext implements BehatContext
{
    use FlowBootstrapTrait;

    use CRTestSuiteTrait;
    use CRBehavioralTestsSubjectProvider;
    use MigrationsTrait;

    protected Environment $environment;

    protected ContentRepositoryRegistry $contentRepositoryRegistry;
    protected PersistenceManagerInterface $persistenceManager;

    public function __construct()
    {
        self::bootstrapFlow();
        $this->environment = $this->getObject(Environment::class);
        $this->contentRepositoryRegistry = $this->getObject(ContentRepositoryRegistry::class);
        $this->persistenceManager = $this->getObject(PersistenceManagerInterface::class);
    }

    /*
     * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
     *  Please don't add any generic step definitions here and use   *
     *  a dedicated trait instead to keep this main class tidied up. *
     * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
     */

    /**
     * @BeforeScenario
     */
    public function resetContentRepositoryComponents(): void
    {
        FakeContentDimensionSourceFactory::reset();
        FakeNodeTypeManagerFactory::reset();
    }

    protected function getContentRepositoryService(
        ContentRepositoryServiceFactoryInterface $factory
    ): ContentRepositoryServiceInterface {
        return $this->contentRepositoryRegistry->buildService(
            $this->currentContentRepository->id,
            $factory
        );
    }

    protected function createContentRepository(
        ContentRepositoryId $contentRepositoryId
    ): ContentRepository {
        $this->contentRepositoryRegistry->resetFactoryInstance($contentRepositoryId);
        $contentRepository = $this->contentRepositoryRegistry->get($contentRepositoryId);
        FakeContentDimensionSourceFactory::reset();
        FakeNodeTypeManagerFactory::reset();

        return $contentRepository;
    }

}
