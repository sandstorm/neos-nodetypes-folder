@flowEntities @contentrepository
Feature: Same uriPath on different sites is not a collision

  In a multi-site content repository all sites share one DocumentUriPath
  projection table, but uriPaths are site-relative: the router disambiguates
  by the request's site (domain), so "/services" on site A and "/services"
  on site B coexist without conflict. The collision check must therefore
  only compare rows within the candidate's own site — otherwise perfectly
  legal commands (e.g. a node migration re-setting uriPathSegments across
  all sites) are rejected with a false UriPathCollisionDetected.

  Collisions within one site must of course still be rejected — including
  a move that crosses over into a site where the segment is already taken.

      lady-eleonode-rootford
      ├─ homepage-a            (site-1, http://domain1.tld)
      │  ├─ services-a         (segment "services")
      │  └─ about-a            (segment "about")
      └─ homepage-b            (site-2, http://domain2.tld)
         ├─ services-b         (segment "services")   ← same segment as services-a: legal
         └─ page-b             (segment "page-b")

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
    # Creating services-b is itself part of the regression test: its segment
    # already exists on site-1, which a non-site-scoped check would reject.
    And the following CreateNodeAggregateWithNode commands are executed:
      | nodeAggregateId | parentNodeAggregateId  | nodeTypeName                | initialPropertyValues            | nodeName |
      | homepage-a      | lady-eleonode-rootford | Neos.Neos:Test.Routing.Page | {"uriPathSegment": "ignore-me"}  | site-1   |
      | services-a      | homepage-a             | Neos.Neos:Test.Routing.Page | {"uriPathSegment": "services"}   | node-a1  |
      | about-a         | homepage-a             | Neos.Neos:Test.Routing.Page | {"uriPathSegment": "about"}      | node-a2  |
      | homepage-b      | lady-eleonode-rootford | Neos.Neos:Test.Routing.Page | {"uriPathSegment": "ignore-me"}  | site-2   |
      | services-b      | homepage-b             | Neos.Neos:Test.Routing.Page | {"uriPathSegment": "services"}   | node-b1  |
      | page-b          | homepage-b             | Neos.Neos:Test.Routing.Page | {"uriPathSegment": "page-b"}     | node-b2  |
    And A site exists for node name "site-1" and domain "http://domain1.tld"
    And A site exists for node name "site-2" and domain "http://domain2.tld"
    And the sites configuration is:
    """yaml
    Neos:
      Neos:
        sites:
          'site-1':
            preset: 'default'
            uriPathSuffix: ''
            contentDimensions:
              resolver:
                factoryClassName: Neos\Neos\FrontendRouting\DimensionResolution\Resolver\NoopResolverFactory
          'site-2':
            preset: 'default'
            uriPathSuffix: ''
            contentDimensions:
              resolver:
                factoryClassName: Neos\Neos\FrontendRouting\DimensionResolution\Resolver\NoopResolverFactory
    """

  Scenario: Both sites serve the same uriPath independently
    When I am on URL "http://domain1.tld/services"
    Then the matched node should be "services-a" in dimension "{}"
    When I am on URL "http://domain2.tld/services"
    Then the matched node should be "services-b" in dimension "{}"

  Scenario: Re-setting a segment that another site also uses is accepted (node migration case)
    # A migration lowercasing all uriPathSegments re-sets unchanged values;
    # the resulting SetNodeProperties must not trip over the other site's row.
    When the command SetNodeProperties is executed with payload:
      | Key                       | Value                          |
      | nodeAggregateId           | "services-b"                   |
      | originDimensionSpacePoint | {}                             |
      | propertyValues            | {"uriPathSegment": "services"} |
    And I am on URL "http://domain2.tld/"
    Then the node "services-b" in dimension "{}" should resolve to URL "/services"

  Scenario: Renaming to a segment used only on another site is accepted
    When the command SetNodeProperties is executed with payload:
      | Key                       | Value                       |
      | nodeAggregateId           | "page-b"                    |
      | originDimensionSpacePoint | {}                          |
      | propertyValues            | {"uriPathSegment": "about"} |
    And I am on URL "http://domain2.tld/"
    Then the node "page-b" in dimension "{}" should resolve to URL "/about"

  Scenario: Renaming to a segment already used on the same site is still rejected
    When the command SetNodeProperties is executed with payload and exceptions are caught:
      | Key                       | Value                          |
      | nodeAggregateId           | "page-b"                       |
      | originDimensionSpacePoint | {}                             |
      | propertyValues            | {"uriPathSegment": "services"} |
    Then the last command should have thrown an exception of type "UriPathCollisionDetected"

  Scenario: Moving a page into a site where its segment is taken is still rejected
    # The collision must be checked against the *target* parent's site.
    When the command MoveNodeAggregate is executed with payload and exceptions are caught:
      | Key                                 | Value        |
      | nodeAggregateId                     | "services-b" |
      | dimensionSpacePoint                 | {}           |
      | newParentNodeAggregateId            | "homepage-a" |
      | newSucceedingSiblingNodeAggregateId | null         |
    Then the last command should have thrown an exception of type "UriPathCollisionDetected"

  Scenario: Moving a page into another site with a free segment is accepted
    When the command MoveNodeAggregate is executed with payload:
      | Key                                 | Value        |
      | nodeAggregateId                     | "page-b"     |
      | dimensionSpacePoint                 | {}           |
      | newParentNodeAggregateId            | "homepage-a" |
      | newSucceedingSiblingNodeAggregateId | null         |
    And I am on URL "http://domain1.tld/"
    Then the node "page-b" in dimension "{}" should resolve to URL "/page-b"
