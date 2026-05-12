@flowEntities @contentrepository
Feature: Folder transparency in URL routing (Tree A, single dimension)

  A transparent Document.Folder must not appear in resolved URLs and must not
  be addressable as a URL segment when matching. Descendants of the folder are
  routed as if the folder were not there. The folder's own projection row still
  stores its segment in `uripath` so descendant rewrites can locate it; this is
  load-bearing for the parent-chain walk in `FolderUriPathLogic`.

  Tree A:

      lady-eleonode-rootford (Neos.Neos:Sites)
      └─ site-of-folders                    (Test.Routing.Page, name "node1", segment "site-ignored")
         ├─ folder-a                        (Document.Folder, hide=true, segment "folder-a")
         │  └─ child-in-folder              (Test.Routing.Page, segment "child")
         └─ sibling-of-folder               (Test.Routing.Page, segment "sibling")

  Background:
    Given using no content dimensions
    And using the following node types:
    """yaml
    'Neos.Neos:Sites':
      superTypes:
        'Neos.ContentRepository:Root': true
    'Neos.Neos:Document': {}
    'Neos.Neos:Content': {}
    'Neos.Neos:Test.Routing.Page':
      superTypes:
        'Neos.Neos:Document': true
      properties:
        uriPathSegment:
          type: string
    'Sandstorm.NodeTypes.Folder:Mixin.HideUriSegment':
      abstract: true
      properties:
        hideSegmentInUriPath:
          type: boolean
          defaultValue: true
    'Sandstorm.NodeTypes.Folder:Document.Folder':
      superTypes:
        'Neos.Neos:Document': true
        'Sandstorm.NodeTypes.Folder:Mixin.HideUriSegment': true
      properties:
        uriPathSegment:
          type: string
    """
    And using identifier "default", I define a content repository
    And I am in content repository "default"
    And I am user identified by "initiating-user-identifier"
    When the command CreateRootWorkspace is executed with payload:
      | Key                | Value           |
      | workspaceName      | "live"          |
      | newContentStreamId | "cs-identifier" |
    And I am in workspace "live" and dimension space point {}
    And the command CreateRootNodeAggregateWithNode is executed with payload:
      | Key             | Value                    |
      | nodeAggregateId | "lady-eleonode-rootford" |
      | nodeTypeName    | "Neos.Neos:Sites"        |
    And the following CreateNodeAggregateWithNode commands are executed:
      | nodeAggregateId     | parentNodeAggregateId  | nodeTypeName                                  | initialPropertyValues                                          | nodeName |
      | site-of-folders     | lady-eleonode-rootford | Neos.Neos:Test.Routing.Page                   | {"uriPathSegment": "site-ignored"}                             | node1    |
      | folder-a            | site-of-folders        | Sandstorm.NodeTypes.Folder:Document.Folder    | {"uriPathSegment": "folder-a", "hideSegmentInUriPath": true}   | folderA  |
      | child-in-folder     | folder-a               | Neos.Neos:Test.Routing.Page                   | {"uriPathSegment": "child"}                                    | child    |
      | sibling-of-folder   | site-of-folders        | Neos.Neos:Test.Routing.Page                   | {"uriPathSegment": "sibling"}                                  | sibling  |
    And A site exists for node name "node1"
    And the sites configuration is:
    """yaml
    Neos:
      Neos:
        sites:
          'node1':
            preset: 'default'
            uriPathSuffix: ''
            contentDimensions:
              resolver:
                factoryClassName: Neos\Neos\FrontendRouting\DimensionResolution\Resolver\NoopResolverFactory
    """

  Scenario: Resolving — folder segment is omitted from descendant URLs, sibling unaffected
    When I am on URL "/"
    Then the node "child-in-folder" in dimension "{}" should resolve to URL "/child"
    And the node "sibling-of-folder" in dimension "{}" should resolve to URL "/sibling"

  Scenario: Matching — descendant matches at the transparent URL, opaque path matches nothing
    When I am on URL "/child"
    Then the matched node should be "child-in-folder" in dimension "{}"
    When I am on URL "/sibling"
    Then the matched node should be "sibling-of-folder" in dimension "{}"
    When I am on URL "/folder-a/child"
    Then No node should match URL "/folder-a/child"

  Scenario: Folder's own projection row stores its segment for descendant rewrites
    Then I expect the documenturipath table to contain exactly:
      | nodeaggregateid          | uripath    | hideurisegment |
      | "lady-eleonode-rootford" | ""         | 0              |
      | "site-of-folders"        | ""         | 0              |
      | "folder-a"               | "folder-a" | 1              |
      | "child-in-folder"        | "child"    | 0              |
      | "sibling-of-folder"      | "sibling"  | 0              |
