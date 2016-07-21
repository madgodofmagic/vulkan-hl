{-# language FlexibleInstances #-}
{-# language MultiParamTypeClasses #-}
{-# language TypeSynonymInstances #-}
{-# language DuplicateRecordFields #-}
{-# language PatternSynonyms #-}
{-# language DataKinds #-}
{-# language GeneralizedNewtypeDeriving #-}

module Graphics.Vulkan.Core where

import Control.Monad
import Data.Bits
import Data.Int
import Data.Vector.Storable.Sized as V hiding (head, length)
import Data.Void
import Data.Word
import Foreign.C
import Foreign.Marshal
import Foreign.Ptr
import Foreign.Storable
import Graphics.Vulkan.Internal.Marshal
import Graphics.Vulkan.Raw
import SDL.Internal.Types (Window(Window))
import SDL.Video.Vulkan

type LayerName = String
type ExtensionName = String
data Version = Version Word Word Word

instance WithVk Version Word32 where
  withVk (Version a b c) f = f v
    where v = vkMakeVersion (fromIntegral a) (fromIntegral b) (fromIntegral c)

data ApplicationInfo = ApplicationInfo { applicationName :: String
                                       , applicationVersion :: Version
                                       , engineName :: String
                                       , engineVersion :: Version
                                       , apiVersion :: Version
                                       }

instance WithVk ApplicationInfo VkApplicationInfo where
  withVk a f =
    (wrapString (applicationName a) $
     wrapValue (applicationVersion a) $
     wrapString (engineName a) $
     wrapValue (engineVersion a) $
     wrapValue (apiVersion a)
     f)
    (VkApplicationInfo VK_STRUCTURE_TYPE_APPLICATION_INFO nullPtr)

data InstanceCreateInfo = InstanceCreateInfo { applicationInfo :: ApplicationInfo
                                             , instanceLayers :: [LayerName]
                                             , instanceExtensions :: [ExtensionName]
                                             }

instance WithVk InstanceCreateInfo VkInstanceCreateInfo where
  withVk (InstanceCreateInfo ai l e) f =
    (wrapInPtr ai $
     wrapInArray l $
     wrapInArray e
     f)
    (VkInstanceCreateInfo VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO nullPtr (VkInstanceCreateFlags zeroBits))

data Extension = Extension { extensionName :: ExtensionName
                           , extensionVersion :: Word
                           }
               deriving (Eq, Ord, Show, Read)

instance FromVk Extension VkExtensionProperties where
  fromVk (VkExtensionProperties name version) = do
    let nameList = Prelude.reverse (V.foldl' (flip (:)) [] name)
    withArray nameList (\pname -> do
                           n <- peekCString pname
                           pure $ Extension n (fromIntegral version)
                       )

hasFlag :: Bits a => a -> a -> Bool
hasFlag a b = a .|. b /= zeroBits

type Instance = Handle VkInstance

createInstance :: InstanceCreateInfo -> IO Instance
createInstance a =
  (wrapInPtr a $
   wrapConst nullPtr $
   wrapOutPtr id
  ) vkCreateInstance

destroyInstance :: Instance -> IO ()
destroyInstance i = (wrapValue i $
                     wrapConst nullPtr id) vkDestroyInstance

deviceExtensionProperties :: IO [Extension]
deviceExtensionProperties = wrapCountArray $ vkEnumerateInstanceExtensionProperties nullPtr

type PhysicalDevice = Handle VkPhysicalDevice

physicalDevices :: Instance -> IO [PhysicalDevice]
physicalDevices i = wrapValue i wrapCountArray vkEnumeratePhysicalDevices

type QueueFlags = Flags VkQueueFlags

pattern GraphicsQueue :: QueueFlags
pattern GraphicsQueue = Flags VK_QUEUE_GRAPHICS_BIT

data Extent2D = Extent2D { width :: Word
                         , height :: Word
                         }
              deriving (Eq, Ord, Show)

instance FromVk Extent2D VkExtent2D where fromVk (VkExtent2D w h) = Extent2D <$> fromVk w <*> fromVk h
instance WithVk Extent2D VkExtent2D where withVk (Extent2D w h) fn = (wrapValue w $ wrapValue h fn) VkExtent2D

data Extent3D = Extent3D { width :: Word
                         , height :: Word
                         , depth :: Word
                         }
              deriving (Eq, Ord, Show)

instance FromVk Extent3D VkExtent3D where fromVk (VkExtent3D w h d) = Extent3D <$> fromVk w <*> fromVk h <*> fromVk d
instance WithVk Extent3D VkExtent3D where withVk (Extent3D w h d) fn = (wrapValue w $ wrapValue h $ wrapValue d fn) VkExtent3D

ignored :: Word
ignored = fromIntegral VK_QUEUE_FAMILY_IGNORED

data QueueFamilyProperties = QueueFamilyProperties { flags :: QueueFlags
                                                   , count :: Word
                                                   , timestampValidBits :: Word
                                                   , minImageTransferGranularity :: Extent3D
                                                   }
                           deriving (Eq, Ord, Show)

instance FromVk QueueFamilyProperties VkQueueFamilyProperties where
  fromVk (VkQueueFamilyProperties fl c tvb mitg) =
    QueueFamilyProperties <$> fromVk fl <*> fromVk c <*> fromVk tvb <*> fromVk mitg

instance WithVk QueueFamilyProperties VkQueueFamilyProperties where
  withVk (QueueFamilyProperties fl c tvb mitg) f =
    (wrapValue fl $ wrapValue c $ wrapValue tvb $ wrapValue mitg f) VkQueueFamilyProperties

queueFamilyProperties :: PhysicalDevice -> IO [QueueFamilyProperties]
queueFamilyProperties pd = wrapValue pd wrapCountArray vkGetPhysicalDeviceQueueFamilyProperties

type Surface = Handle VkSurfaceKHR

createSurface :: Window -> Instance -> IO Surface
createSurface (Window w) (Handle i) = Handle <$>
  alloca (\ps -> do
             r <- createSurfaceFFI w i ps
             unless r $ error "SDL_CreateVulkanSurface failed"
             peek ps)

queueFamilySupportsPresent :: PhysicalDevice -> Word -> Surface -> IO Bool
queueFamilySupportsPresent pd qi s =
  (wrapValue pd $ wrapValue qi $ wrapValue s $ wrapOutPtr id)
  vkGetPhysicalDeviceSurfaceSupportKHR

data QueueCreateInfo = QueueCreateInfo { queueCreateFamily :: Word
                                       , queuePriorities :: [Float]
                                       }

instance WithVk QueueCreateInfo VkDeviceQueueCreateInfo where
  withVk (QueueCreateInfo i c) f =
    wrapInArray c
    f $ VkDeviceQueueCreateInfo VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO nullPtr
    (VkDeviceQueueCreateFlags zeroBits) (fromIntegral i)

data DeviceCreateInfo = DeviceCreateInfo { deviceQueues :: [QueueCreateInfo]
                                         , deviceLayers :: [LayerName]
                                         , deviceExtensions :: [ExtensionName]
                                         }

instance WithVk DeviceCreateInfo VkDeviceCreateInfo where
  withVk (DeviceCreateInfo q l e) f =
    (wrapInArray q $
     wrapInArray l $
     wrapInArray e $
     f . ($ nullPtr))
    (VkDeviceCreateInfo VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO nullPtr (VkDeviceCreateFlags zeroBits))

type Device = Handle VkDevice

createDevice :: PhysicalDevice -> DeviceCreateInfo -> IO Device
createDevice pd a =
  (wrapValue pd $ wrapInPtr a $ wrapConst nullPtr $ wrapOutPtr id)
  vkCreateDevice

type Queue = Handle VkQueue

getQueue :: Device -> Word -> Word -> IO Queue
getQueue d f i =
  (wrapValue d $ wrapValue f $ wrapValue i $ wrapOutPtr id)
  vkGetDeviceQueue

type CommandPoolCreateFlags = Flags VkCommandPoolCreateFlags

pattern CreateResetCommandBuffer :: CommandPoolCreateFlags
pattern CreateResetCommandBuffer = Flags VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT

data CommandPoolCreateInfo = CommandPoolCreateInfo { flags :: CommandPoolCreateFlags
                                                   , queueFamilyIndex :: Word
                                                   }

instance WithVk CommandPoolCreateInfo VkCommandPoolCreateInfo where
  withVk (CommandPoolCreateInfo (Flags fl) qfi) f =
    f $ VkCommandPoolCreateInfo VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO nullPtr
    fl (fromIntegral qfi)

type CommandPool = Handle VkCommandPool

createCommandPool :: Device -> CommandPoolCreateInfo -> IO CommandPool
createCommandPool d ci =
  (wrapValue d $ wrapInPtr ci $ wrapConst nullPtr $ wrapOutPtr id)
  vkCreateCommandPool

type Format = Enumerator VkFormat

pattern UndefinedFormat :: Format
pattern UndefinedFormat = Enumerator VK_FORMAT_UNDEFINED
pattern B8G8R8A8Srgb :: Format
pattern B8G8R8A8Srgb = Enumerator VK_FORMAT_B8G8R8A8_SRGB

type ColorSpace = Enumerator VkColorSpaceKHR

data SurfaceFormat = SurfaceFormat { format :: Format
                                   , colorSpace :: ColorSpace
                                   }
                   deriving (Eq, Ord, Show)

instance FromVk SurfaceFormat VkSurfaceFormatKHR where
  fromVk (VkSurfaceFormatKHR f cs) = pure (SurfaceFormat (Enumerator f) (Enumerator cs))

instance WithVk SurfaceFormat VkSurfaceFormatKHR where
  withVk (SurfaceFormat (Enumerator f) (Enumerator cs)) fn = fn (VkSurfaceFormatKHR f cs)

surfaceFormats :: PhysicalDevice -> Surface -> IO [SurfaceFormat]
surfaceFormats pd s =
  (wrapValue pd $ wrapValue s wrapCountArray)
  vkGetPhysicalDeviceSurfaceFormatsKHR

data SurfaceCapabilities = SurfaceCapabilities { minImageCount :: Word
                                               , maxImageCount :: Word
                                               , currentExtent :: Extent2D
                                               , minImageExtent :: Extent2D
                                               , maxImageExtent :: Extent2D
                                               , maxImageArrayLayers :: Word
                                               , supportedTransforms :: SurfaceTransformFlags
                                               , currentTransform :: SurfaceTransformFlags
                                               , supportedCompositeAlpha :: CompositeAlphaFlags
                                               , supportedUsageFlags :: ImageUsageFlags
                                               }
                         deriving (Eq, Ord, Show)

instance FromVk SurfaceCapabilities VkSurfaceCapabilitiesKHR where
  fromVk (VkSurfaceCapabilitiesKHR miic maic ce miie maie maial st ct sca suf) =
    SurfaceCapabilities <$> fromVk miic <*> fromVk maic <*> fromVk ce <*> fromVk miie
    <*> fromVk maie <*> fromVk maial <*> fromVk st <*> fromVk ct <*> fromVk sca <*> fromVk suf

instance WithVk SurfaceCapabilities VkSurfaceCapabilitiesKHR where
  withVk (SurfaceCapabilities miic maic ce miie maie maial st ct sca suf) f =
    (wrapValue miic $ wrapValue maic $ wrapValue ce $ wrapValue miie $ wrapValue maie $ wrapValue maial $
     wrapValue st $ wrapValue ct $ wrapValue sca $ wrapValue suf f) VkSurfaceCapabilitiesKHR

surfaceCapabilities :: PhysicalDevice -> Surface -> IO SurfaceCapabilities
surfaceCapabilities pd s =
  (wrapValue pd $ wrapValue s $ wrapOutPtr id)
  vkGetPhysicalDeviceSurfaceCapabilitiesKHR

type CommandBufferLevel = Enumerator VkCommandBufferLevel

pattern Primary :: CommandBufferLevel
pattern Primary = Enumerator VK_COMMAND_BUFFER_LEVEL_PRIMARY

type CommandBuffer = Handle VkCommandBuffer

allocateCommandBuffers :: Device -> CommandPool -> CommandBufferLevel -> Word -> IO [CommandBuffer]
allocateCommandBuffers d (Handle cp) (Enumerator l) n =
  (wrapValue d $
   wrapInPtr (VkCommandBufferAllocateInfo VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO nullPtr cp l (fromIntegral n)) $
   wrapOutArray n id)
  vkAllocateCommandBuffers

allocateCommandBuffer :: Device -> CommandPool -> CommandBufferLevel -> IO CommandBuffer
allocateCommandBuffer d cp l = head <$> allocateCommandBuffers d cp l 1

type SwapchainCreateFlags = Flags VkSwapchainCreateFlagsKHR

type ImageUsageFlags = Flags VkImageUsageFlagBits

pattern ColorAttachment :: ImageUsageFlags
pattern ColorAttachment = Flags VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT

type SharingMode = Enumerator VkSharingMode

pattern Exclusive :: SharingMode
pattern Exclusive = Enumerator VK_SHARING_MODE_EXCLUSIVE

type SurfaceTransformFlags = Flags VkSurfaceTransformFlagsKHR

type CompositeAlphaFlags = Flags VkCompositeAlphaFlagBitsKHR

pattern Opaque :: CompositeAlphaFlags
pattern Opaque = Flags VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR

type PresentMode = Enumerator VkPresentModeKHR

pattern Fifo :: PresentMode
pattern Fifo = Enumerator VK_PRESENT_MODE_FIFO_KHR

data SwapchainCreateInfo = SwapchainCreateInfo { flags :: SwapchainCreateFlags
                                               , surface :: Surface
                                               , minImageCount :: Word
                                               , imageFormat :: SurfaceFormat
                                               , imageExtent :: Extent2D
                                               , imageArrayLayers :: Word
                                               , imageUsage :: ImageUsageFlags
                                               , imageSharingMode :: SharingMode
                                               , queueFamilyIndices :: [Word]
                                               , preTransform :: SurfaceTransformFlags
                                               , compositeAlpha :: CompositeAlphaFlags
                                               , presentMode :: PresentMode
                                               , clipped :: Bool
                                               }

instance WithVk SwapchainCreateInfo VkSwapchainCreateInfoKHR where
  withVk (SwapchainCreateInfo f s mic (SurfaceFormat imf imcs) ie ial iu ism qfi pt ca pm c) fn =
    (wrapValue f $
     wrapValue s $
     wrapValue mic $
     wrapValue imf $
     wrapValue imcs $
     wrapValue ie $
     wrapValue ial $
     wrapValue iu $
     wrapValue ism $
     wrapInArray qfi $
     wrapValue pt $
     wrapValue ca $
     wrapValue pm $
     wrapValue c $
     wrapConst (VkSwapchainKHR 0)
     fn)
    (VkSwapchainCreateInfoKHR VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR nullPtr)

type Swapchain = Handle VkSwapchainKHR

createSwapchain :: Device -> SwapchainCreateInfo -> IO Swapchain
createSwapchain d ci =
  (wrapValue d $ wrapInPtr ci $ wrapConst nullPtr $ wrapOutPtr id)
  vkCreateSwapchainKHR

swapchainImages :: Device -> Swapchain -> IO [Image]
swapchainImages d s =
  (wrapValue d $ wrapValue s wrapCountArray)
  vkGetSwapchainImagesKHR

type FNDebugReportCallback =
  (VkDebugReportFlagsEXT ->
     VkDebugReportObjectTypeEXT ->
       Word64 ->
         CSize -> Int32 -> Ptr CChar -> Ptr CChar -> Ptr Void -> IO VkBool32)

type DebugReportCallbackFun =
  (VkDebugReportFlagsEXT ->
     VkDebugReportObjectTypeEXT ->
       Word64 ->
         CSize -> Int32 -> String -> String -> IO Bool)

foreign import ccall "wrapper" mkDebugReportCallback :: FNDebugReportCallback -> IO PFN_vkDebugReportCallbackEXT

data DebugReportCallback = DebugReportCallback VkDebugReportCallbackEXT PFN_vkDebugReportCallbackEXT
                         deriving (Eq, Ord, Show)

type FNcreateDebugReportCallback =
  VkInstance ->
  Ptr VkDebugReportCallbackCreateInfoEXT ->
    Ptr VkAllocationCallbacks -> Ptr VkDebugReportCallbackEXT -> IO VkResult

type DebugReportFlags = Flags VkDebugReportFlagsEXT

pattern Error :: DebugReportFlags
pattern Error = Flags VK_DEBUG_REPORT_ERROR_BIT_EXT
pattern Warning :: DebugReportFlags
pattern Warning = Flags VK_DEBUG_REPORT_WARNING_BIT_EXT
pattern PerformanceWarning :: DebugReportFlags
pattern PerformanceWarning = Flags VK_DEBUG_REPORT_PERFORMANCE_WARNING_BIT_EXT
pattern Information :: DebugReportFlags
pattern Information = Flags VK_DEBUG_REPORT_INFORMATION_BIT_EXT
pattern Debug :: DebugReportFlags
pattern Debug = Flags VK_DEBUG_REPORT_DEBUG_BIT_EXT

createDebugReportCallback :: Instance -> DebugReportFlags -> DebugReportCallbackFun -> IO DebugReportCallback
createDebugReportCallback i (Flags flags) cb = do
  cbPtr <- mkDebugReportCallback wrappedCallback
  let ci = VkDebugReportCallbackCreateInfoEXT VK_STRUCTURE_TYPE_DEBUG_REPORT_CALLBACK_CREATE_INFO_EXT nullPtr flags cbPtr nullPtr
  drc <- (wrapValue i $
          wrapInPtr (ci :: VkDebugReportCallbackCreateInfoEXT) $
          wrapConst nullPtr $
          wrapOutPtr id)
    vkCreateDebugReportCallbackEXT
  pure $ DebugReportCallback drc cbPtr
  where
    wrappedCallback :: FNDebugReportCallback
    wrappedCallback f ot o l mc lp m _ = do
      r <- join $ cb f ot o l mc <$> peekCString lp <*> peekCString m
      pure $ VkBool32 $ if r then 1 else 0

type ImageViewCreateFlags = Flags VkImageViewCreateFlags

type ImageViewType = Enumerator VkImageViewType

pattern Type2D :: ImageViewType
pattern Type2D = Enumerator VK_IMAGE_VIEW_TYPE_2D

type ComponentSwizzle = Enumerator VkComponentSwizzle

pattern R :: ComponentSwizzle
pattern R = Enumerator VK_COMPONENT_SWIZZLE_R
pattern G :: ComponentSwizzle
pattern G = Enumerator VK_COMPONENT_SWIZZLE_G
pattern B :: ComponentSwizzle
pattern B = Enumerator VK_COMPONENT_SWIZZLE_B
pattern A :: ComponentSwizzle
pattern A = Enumerator VK_COMPONENT_SWIZZLE_A

data ComponentMapping = ComponentMapping { red :: ComponentSwizzle
                                         , green :: ComponentSwizzle
                                         , blue :: ComponentSwizzle
                                         , alpha :: ComponentSwizzle
                                         }
                      deriving (Eq, Ord, Show)

instance FromVk ComponentMapping VkComponentMapping where
  fromVk (VkComponentMapping r g b a) =
    pure (ComponentMapping (Enumerator r) (Enumerator g) (Enumerator b) (Enumerator a))

instance WithVk ComponentMapping VkComponentMapping where
  withVk (ComponentMapping (Enumerator r) (Enumerator g) (Enumerator b) (Enumerator a)) fn =
    fn (VkComponentMapping r g b a)

type ImageAspectFlags = Flags VkImageAspectFlagBits

pattern Color :: ImageAspectFlags
pattern Color = Flags VK_IMAGE_ASPECT_COLOR_BIT

data ImageSubresourceRange = ImageSubresourceRange { aspectMask :: ImageAspectFlags
                                                   , baseMipLevel :: Word
                                                   , levelCount :: Word
                                                   , baseArrayLayer :: Word
                                                   , layerCount :: Word
                                                   }
                           deriving (Eq, Ord, Show)

instance FromVk ImageSubresourceRange VkImageSubresourceRange where
  fromVk (VkImageSubresourceRange am bml lec bal lac) =
    ImageSubresourceRange <$> fromVk am <*> fromVk bml <*> fromVk lec <*> fromVk bal <*> fromVk lac
instance WithVk ImageSubresourceRange VkImageSubresourceRange where
  withVk (ImageSubresourceRange am bml lec bal lac) fn =
    (wrapValue am $ wrapValue bml $ wrapValue lec $ wrapValue bal $ wrapValue lac fn) VkImageSubresourceRange

type Image = Handle VkImage

data ImageViewCreateInfo = ImageViewCreateInfo { flags :: ImageViewCreateFlags
                                               , image :: Image
                                               , viewType :: ImageViewType
                                               , format :: Format
                                               , components :: ComponentMapping
                                               , subresourceRange :: ImageSubresourceRange
                                               }

instance WithVk ImageViewCreateInfo VkImageViewCreateInfo where
  withVk (ImageViewCreateInfo f i vt fo c sr) fn =
    (wrapValue f $ wrapValue i $ wrapValue vt $ wrapValue fo $ wrapValue c $ wrapValue sr fn)
    (VkImageViewCreateInfo VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO nullPtr)

type ImageView = Handle VkImageView

createImageView :: Device -> ImageViewCreateInfo -> IO ImageView
createImageView d ci =
  (wrapValue d $ wrapInPtr ci $ wrapConst nullPtr $ wrapOutPtr id)
  vkCreateImageView

type AttachmentDescriptionFlags = Flags VkAttachmentDescriptionFlagBits

type SampleCountFlags = Flags VkSampleCountFlagBits

pattern Sample1 :: SampleCountFlags
pattern Sample1 = Flags VK_SAMPLE_COUNT_1_BIT

type AttachmentLoadOp = Enumerator VkAttachmentLoadOp

pattern Clear :: AttachmentLoadOp
pattern Clear = Enumerator VK_ATTACHMENT_LOAD_OP_CLEAR
pattern DontCareLoad :: AttachmentLoadOp
pattern DontCareLoad = Enumerator VK_ATTACHMENT_LOAD_OP_DONT_CARE

type AttachmentStoreOp = Enumerator VkAttachmentStoreOp

pattern Store :: AttachmentStoreOp
pattern Store = Enumerator VK_ATTACHMENT_STORE_OP_STORE

pattern DontCareStore :: AttachmentStoreOp
pattern DontCareStore = Enumerator VK_ATTACHMENT_STORE_OP_DONT_CARE

type ImageLayout = Enumerator VkImageLayout

pattern UndefinedLayout :: ImageLayout
pattern UndefinedLayout = Enumerator VK_IMAGE_LAYOUT_UNDEFINED
pattern ColorAttachmentOptimal :: ImageLayout
pattern ColorAttachmentOptimal = Enumerator VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
pattern PresentSource :: ImageLayout
pattern PresentSource = Enumerator VK_IMAGE_LAYOUT_PRESENT_SRC_KHR

data AttachmentDescription = AttachmentDescription { flags :: AttachmentDescriptionFlags
                                                   , format :: Format
                                                   , samples :: SampleCountFlags
                                                   , loadOp :: AttachmentLoadOp
                                                   , storeOp :: AttachmentStoreOp
                                                   , stencilLoadOp :: AttachmentLoadOp
                                                   , stencilStoreOp :: AttachmentStoreOp
                                                   , initialLayout :: ImageLayout
                                                   , finalLayout :: ImageLayout
                                                   }
                             deriving (Eq, Ord, Show)

instance FromVk AttachmentDescription VkAttachmentDescription where
  fromVk (VkAttachmentDescription f fo s lo so slo sso il fl) =
    pure (AttachmentDescription (Flags f) (Enumerator fo) (Flags s) (Enumerator lo)
          (Enumerator so) (Enumerator slo) (Enumerator sso) (Enumerator il) (Enumerator fl))
instance WithVk AttachmentDescription VkAttachmentDescription where
  withVk (AttachmentDescription (Flags f) (Enumerator fo) (Flags s) (Enumerator lo)
          (Enumerator so) (Enumerator slo) (Enumerator sso) (Enumerator il) (Enumerator fl)) fn =
    fn (VkAttachmentDescription f fo s lo so slo sso il fl)

type SubpassDescriptionFlags = Flags VkSubpassDescriptionFlags

type PipelineBindPoint = Enumerator VkPipelineBindPoint

pattern GraphicsBindPoint :: PipelineBindPoint
pattern GraphicsBindPoint = Enumerator VK_PIPELINE_BIND_POINT_GRAPHICS

data AttachmentReference = AttachmentReference { attachment :: Word
                                               , layout :: ImageLayout
                                               }
                         deriving (Eq, Ord, Show)

instance WithVk AttachmentReference VkAttachmentReference where
  withVk (AttachmentReference a l) fn =
    (wrapValue a $ wrapValue l fn) VkAttachmentReference

  -- TODO hook these up
data SubpassDescription = SubpassDescription { flags :: SubpassDescriptionFlags
                                             , pipelineBindPoint :: PipelineBindPoint
                                             , inputAttachments :: [AttachmentReference]
                                             , colorAttachments :: [AttachmentReference]
                                             -- , pResolveAttachments :: Maybe [AttachmentReference]
                                             -- , depthStencilAttachment :: VkAttachmentReference
                                             , preserveAttachments :: [Word]
                                             }
                        deriving (Eq, Ord, Show)

instance WithVk SubpassDescription VkSubpassDescription where
  withVk (SubpassDescription f pbp ia ca pa) fn =
    (wrapValue f $ wrapValue pbp $ wrapInArray ia $ wrapInArray ca $ wrapConst nullPtr $ wrapConst nullPtr $ wrapInArray pa fn)
    VkSubpassDescription

type RenderPassCreateFlags = Flags VkRenderPassCreateFlags

data RenderPassCreateInfo = RenderPassCreateInfo { flags :: RenderPassCreateFlags
                                                 , attachments :: [AttachmentDescription]
                                                 , subpasses :: [SubpassDescription]
                                                 , dependencies :: [VkSubpassDependency]
                                                 }

instance WithVk RenderPassCreateInfo VkRenderPassCreateInfo where
  withVk (RenderPassCreateInfo f a s d) fn =
    (wrapValue f $ wrapInArray a $ wrapInArray s $ wrapInArray d fn)
    (VkRenderPassCreateInfo VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO nullPtr)

type RenderPass = Handle VkRenderPass

createRenderPass :: Device -> RenderPassCreateInfo -> IO RenderPass
createRenderPass d ci =
  (wrapValue d $ wrapInPtr ci $ wrapConst nullPtr $ wrapOutPtr id) vkCreateRenderPass

type FramebufferCreateFlags = Flags VkFramebufferCreateFlags

data FramebufferCreateInfo = FramebufferCreateInfo { flags :: FramebufferCreateFlags
                                                   , renderPass :: RenderPass
                                                   , attachments :: [ImageView]
                                                   , width :: Word
                                                   , height :: Word
                                                   , layers :: Word
                                                   }

instance WithVk FramebufferCreateInfo VkFramebufferCreateInfo where
  withVk (FramebufferCreateInfo f rp a w h l) fn =
    (wrapValue f $ wrapValue rp $ wrapInArray a $ wrapValue w $ wrapValue h $ wrapValue l fn)
    (VkFramebufferCreateInfo VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO nullPtr)

type Framebuffer = Handle VkFramebuffer

createFramebuffer :: Device -> FramebufferCreateInfo -> IO Framebuffer
createFramebuffer d ci =
  (wrapValue d $ wrapInPtr ci $ wrapConst nullPtr $ wrapOutPtr id)
  vkCreateFramebuffer

type Semaphore = Handle VkSemaphore

createSemaphore :: Device -> IO Semaphore
createSemaphore d =
  (wrapValue d $
   wrapInPtr (VkSemaphoreCreateInfo VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO nullPtr zeroBits) $
   wrapConst nullPtr $
   wrapOutPtr id)
  vkCreateSemaphore

destroySemaphore :: Device -> Semaphore -> IO ()
destroySemaphore d s =
  (wrapValue d $ wrapValue s $ wrapConst nullPtr id)
  vkDestroySemaphore

type Fence = Handle VkFence

nullFence :: Fence
nullFence = Handle $ VkFence 0

acquireNextImage :: Device -> Swapchain -> Semaphore -> IO Word
acquireNextImage d sc s =
  (wrapValue d $ wrapValue sc $ wrapConst maxBound $ wrapValue s $ wrapValue nullFence $ wrapOutPtr id)
  vkAcquireNextImageKHR

beginCommandBuffer :: CommandBuffer -> IO ()
beginCommandBuffer cb =
  (wrapValue cb $ 
   wrapInPtr (VkCommandBufferBeginInfo VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO nullPtr zeroBits nullPtr) id)
  vkBeginCommandBuffer >>= check

endCommandBuffer :: CommandBuffer -> IO ()
endCommandBuffer cb = wrapValue cb id vkEndCommandBuffer >>= check

type AccessFlags = Flags VkAccessFlags

pattern ColorAttachmentWrite :: AccessFlags
pattern ColorAttachmentWrite = Flags VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT
pattern MemoryRead :: AccessFlags
pattern MemoryRead = Flags VK_ACCESS_MEMORY_READ_BIT

data MemoryBarrier = MemoryBarrier { srcAccessMask :: AccessFlags
                                   , dstAccessMask :: AccessFlags
                                   }
                   deriving (Eq, Ord, Show)

instance WithVk MemoryBarrier VkMemoryBarrier where
  withVk (MemoryBarrier (Flags sam) (Flags dam)) f =
    f (VkMemoryBarrier VK_STRUCTURE_TYPE_MEMORY_BARRIER nullPtr sam dam)

type Buffer = Handle VkBuffer

newtype DeviceSize = DeviceSize Word64
                   deriving (Eq, Ord, Show, Num)

instance FromVk DeviceSize VkDeviceSize where
  fromVk (VkDeviceSize s) = pure $ DeviceSize s

instance WithVk DeviceSize VkDeviceSize where
  withVk (DeviceSize s) fn = fn $ VkDeviceSize s

data BufferMemoryBarrier = BufferMemoryBarrier { srcAccessMask :: AccessFlags
                                               , dstAccessMask :: AccessFlags
                                               , srcQueueFamilyIndex :: Word
                                               , dstQueueFamilyIndex :: Word
                                               , buffer :: Buffer
                                               , offset :: DeviceSize
                                               , size :: DeviceSize
                                               }
                         deriving (Eq, Ord, Show)

instance WithVk BufferMemoryBarrier VkBufferMemoryBarrier where
  withVk (BufferMemoryBarrier sam dam sqfi dqfi b o s) f =
    (wrapValue sam $ wrapValue dam $ wrapValue sqfi $ wrapValue dqfi $ wrapValue b $ wrapValue o $ wrapValue s f)
    (VkBufferMemoryBarrier VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER nullPtr)

data ImageMemoryBarrier = ImageMemoryBarrier { srcAccessMask :: AccessFlags
                                             , dstAccessMask :: AccessFlags
                                             , oldLayout :: ImageLayout
                                             , newLayout :: ImageLayout
                                             , srcQueueFamilyIndex :: Word
                                             , dstQueueFamilyIndex :: Word
                                             , image :: Image
                                             , subresourceRange :: ImageSubresourceRange
                                             }

instance WithVk ImageMemoryBarrier VkImageMemoryBarrier where
  withVk (ImageMemoryBarrier sam dam ol nl sqfi dqfi i sr) f =
    (wrapValue sam $ wrapValue dam $ wrapValue ol $ wrapValue nl $ wrapValue sqfi $ wrapValue dqfi $ wrapValue i $ wrapValue sr f)
    (VkImageMemoryBarrier VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER nullPtr)

type PipelineStageFlags = Flags VkPipelineStageFlagBits

pattern AllCommands :: PipelineStageFlags
pattern AllCommands = Flags VK_PIPELINE_STAGE_ALL_COMMANDS_BIT
pattern BottomOfPipe :: PipelineStageFlags
pattern BottomOfPipe = Flags VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT

type DependencyFlags = Flags VkDependencyFlags

cmdPipelineBarrier :: CommandBuffer -> PipelineStageFlags -> PipelineStageFlags -> DependencyFlags ->
                      [MemoryBarrier] -> [BufferMemoryBarrier] -> [ImageMemoryBarrier] -> IO ()
cmdPipelineBarrier cb ssm dsm df mb bmb imb =
  (wrapValue cb $ wrapValue ssm $ wrapValue dsm $ wrapValue df $ wrapInArray mb $ wrapInArray bmb $ wrapInArray imb id)
  vkCmdPipelineBarrier

data Offset2D = Offset2D Int32 Int32
              deriving (Eq, Ord, Show)

instance FromVk Offset2D VkOffset2D where fromVk (VkOffset2D x y) = pure (Offset2D x y)
instance WithVk Offset2D VkOffset2D where withVk (Offset2D x y) fn = fn (VkOffset2D x y)

data Rect2D = Rect2D { offset :: Offset2D
                     , extent :: Extent2D
                     }
            deriving (Eq, Ord, Show)

instance WithVk Rect2D VkRect2D where withVk (Rect2D o e) fn = (wrapValue o $ wrapValue e fn) VkRect2D

data ClearColorValue = FloatColor (Vector 4 Float)
                       | IntColor (Vector 4 Int)
                       | UIntColor (Vector 4 Word)
                       deriving (Eq, Ord, Show)

instance WithVk ClearColorValue VkClearColorValue where
  withVk (FloatColor v) fn = fn $ VkFloat32 $ V.map CFloat v
  withVk (IntColor v) fn = fn $ VkInt32 $ V.map fromIntegral v
  withVk (UIntColor v) fn = fn $ VkUint32 $ V.map fromIntegral v

data ClearDepthStencilValue = ClearDepthStencilValue { depth :: Float
                                                     , stencil :: Word
                                                     }
                            deriving (Eq, Ord, Show)

instance WithVk ClearDepthStencilValue VkClearDepthStencilValue where
  withVk (ClearDepthStencilValue d s) fn = (wrapValue d $ wrapValue s fn) VkClearDepthStencilValue

data ClearValue = ClearColor ClearColorValue
                  | ClearDepthStencil ClearDepthStencilValue
                  deriving (Eq, Ord, Show)

instance WithVk ClearValue VkClearValue where
  withVk (ClearColor v) fn = wrapValue v fn VkColor
  withVk (ClearDepthStencil v) fn = wrapValue v fn VkDepthStencil

data RenderPassBeginInfo = RenderPassBeginInfo { renderPass :: RenderPass
                                               , framebuffer :: Framebuffer
                                               , renderArea :: Rect2D
                                               , clearValues :: [ClearValue]
                                               }

instance WithVk RenderPassBeginInfo VkRenderPassBeginInfo where
  withVk (RenderPassBeginInfo rp fb ra cv) f =
    (wrapValue rp $ wrapValue fb $ wrapValue ra $ wrapInArray cv f)
    (VkRenderPassBeginInfo VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO nullPtr)

type SubpassContents = Enumerator VkSubpassContents

pattern Inline :: SubpassContents
pattern Inline = Enumerator VK_SUBPASS_CONTENTS_INLINE

cmdBeginRenderPass :: CommandBuffer -> RenderPassBeginInfo -> SubpassContents -> IO ()
cmdBeginRenderPass cb bi sc =
  (wrapValue cb $ wrapInPtr bi $ wrapValue sc id)
  vkCmdBeginRenderPass

cmdEndRenderPass :: CommandBuffer -> IO ()
cmdEndRenderPass cb = wrapValue cb id vkCmdEndRenderPass >>= check

data SubmitInfo = SubmitInfo { waitSemaphores :: [(Semaphore, PipelineStageFlags)]
                             , commandBuffers :: [CommandBuffer]
                             , signalSemaphores :: [Semaphore]
                             }

instance WithVk SubmitInfo VkSubmitInfo where
  withVk (SubmitInfo ws cb ss) f =
    wrapInArray (fmap fst ws)
    (wrapInArrayNoCount (fmap snd ws) $
     wrapInArray cb $
     wrapInArray ss f) $
    VkSubmitInfo VK_STRUCTURE_TYPE_SUBMIT_INFO nullPtr

queueSubmit :: Queue -> [SubmitInfo] -> Fence -> IO ()
queueSubmit q si f = (wrapValue q $ wrapInArray si $ wrapValue f id) vkQueueSubmit >>= check

data PresentInfo = PresentInfo { waitSemaphores :: [Semaphore]
                               , swapchains :: [(Swapchain, Word)]
                               }

instance WithVk PresentInfo VkPresentInfoKHR where
  withVk (PresentInfo ws sc) f =
    wrapInArray ws
    (wrapInArray (fst <$> sc) $
     wrapInArrayNoCount (snd <$> sc) $
     wrapConst nullPtr f) $
    VkPresentInfoKHR VK_STRUCTURE_TYPE_PRESENT_INFO_KHR nullPtr

queuePresent :: Queue -> PresentInfo -> IO ()
queuePresent q pi = (wrapValue q $ wrapInPtr pi id) vkQueuePresentKHR >>= check

queueWaitIdle :: Queue -> IO ()
queueWaitIdle q = wrapValue q id vkQueueWaitIdle >>= check

type PipelineCreateFlags = Flags VkPipelineCreateFlags

type PipelineShaderStageCreateFlags = Flags VkPipelineShaderStageCreateFlags

type ShaderStage = Enumerator VkShaderStageFlagBits

type ShaderModule = Handle VkShaderModule

data SpecializationMapEntry = SpecializationMapEntry { constantID :: Word
                                                     , offset :: Word
                                                     , size :: CSize
                                                     }
                            deriving (Eq, Ord, Show)

instance WithVk SpecializationMapEntry VkSpecializationMapEntry where
  withVk (SpecializationMapEntry c o s) fn =
    (wrapValue c $ wrapValue o $ wrapConst s fn)
    VkSpecializationMapEntry

data SpecializationInfo = SpecializationInfo { mapEntries :: [SpecializationMapEntry]
                                             , dataSize :: CSize
                                             , pdata :: Ptr Void
                                             }
                        deriving (Eq, Ord, Show)

instance WithVk SpecializationInfo VkSpecializationInfo where
  withVk (SpecializationInfo me ds p) fn =
    (wrapInArray me $ wrapConst ds $ wrapConst p fn)
    VkSpecializationInfo

data PipelineShaderStageCreateInfo = PipelineShaderStageCreateInfo { flags :: PipelineShaderStageCreateFlags
                                                                   , stage :: ShaderStage
                                                                   , shaderModule :: ShaderModule
                                                                   , name :: String
                                                                   , specializationInfo :: Maybe SpecializationInfo
                                                                   }

instance WithVk PipelineShaderStageCreateInfo VkPipelineShaderStageCreateInfo where
  withVk (PipelineShaderStageCreateInfo f s sm n si) fn =
    (wrapValue f $ wrapValue s $ wrapValue sm $ wrapValue n $ wrapOptPtr si fn)
    (VkPipelineShaderStageCreateInfo VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO nullPtr)

type PipelineVertexInputStateCreateFlags = Flags VkPipelineVertexInputStateCreateFlags

type VertexInputRate = Enumerator VkVertexInputRate

data VertexInputBindingDescription = VertexInputBindingDescription { binding :: Word
                                                                   , stride :: Word
                                                                   , inputRate :: VertexInputRate
                                                                   }
                                   deriving (Eq, Ord, Show)

instance WithVk VertexInputBindingDescription VkVertexInputBindingDescription where
  withVk (VertexInputBindingDescription b s ir) fn =
    (wrapValue b $ wrapValue s $ wrapValue ir fn)
    VkVertexInputBindingDescription

data VertexInputAttributeDescription = VertexInputAttributeDescription { location :: Word
                                                                       , binding :: Word
                                                                       , format :: Format
                                                                       , offset :: Word
                                                                       }
                                     deriving (Eq, Ord, Show)

instance WithVk VertexInputAttributeDescription VkVertexInputAttributeDescription where
  withVk (VertexInputAttributeDescription l b f o) fn =
    (wrapValue l $ wrapValue b $ wrapValue f $ wrapValue o fn)
    VkVertexInputAttributeDescription

data PipelineVertexInputStateCreateInfo = PipelineVertexInputStateCreateInfo
  { flags :: PipelineVertexInputStateCreateFlags
  , vertexBindingDescriptions :: [VertexInputBindingDescription]
  , vertexAttributeDescriptions :: [VertexInputAttributeDescription]
  }
  deriving (Eq, Ord, Show)

instance WithVk PipelineVertexInputStateCreateInfo VkPipelineVertexInputStateCreateInfo where
  withVk (PipelineVertexInputStateCreateInfo f vbd vad) fn =
    (wrapValue f $ wrapInArray vbd $ wrapInArray vad fn)
    (VkPipelineVertexInputStateCreateInfo VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO nullPtr)

type PipelineInputAssemblyStateCreateFlags = Flags VkPipelineInputAssemblyStateCreateFlags

type PrimitiveTopology = Enumerator VkPrimitiveTopology

data PipelineInputAssemblyStateCreateInfo = PipelineInputAssemblyStateCreateInfo
  { flags :: PipelineInputAssemblyStateCreateFlags
  , topology :: PrimitiveTopology
  , primitiveRestartEnable :: Bool
  }
  deriving (Eq, Ord, Show)

instance WithVk PipelineInputAssemblyStateCreateInfo VkPipelineInputAssemblyStateCreateInfo where
  withVk (PipelineInputAssemblyStateCreateInfo f t p) fn =
    (wrapValue f $ wrapValue t $ wrapValue p fn)
    (VkPipelineInputAssemblyStateCreateInfo VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO nullPtr)

type PipelineTessellationStateCreateFlags = Flags VkPipelineTessellationStateCreateFlags

data PipelineTessellationStateCreateInfo = PipelineTessellationStateCreateInfo
  { flags :: PipelineTessellationStateCreateFlags
  , patchControlPoints :: Word
  }
  deriving (Eq, Ord, Show)

instance WithVk PipelineTessellationStateCreateInfo VkPipelineTessellationStateCreateInfo where
  withVk (PipelineTessellationStateCreateInfo f p) fn =
    (wrapValue f $ wrapValue p fn)
    (VkPipelineTessellationStateCreateInfo VK_STRUCTURE_TYPE_PIPELINE_TESSELLATION_STATE_CREATE_INFO nullPtr)

type PipelineViewportStateCreateFlags = Flags VkPipelineViewportStateCreateFlags

data Viewport = Viewport { x :: Float
                         , y :: Float
                         , width :: Float
                         , height :: Float
                         , minDepth :: Float
                         , maxDepth :: Float
                         }
              deriving (Eq, Ord, Show)

instance WithVk Viewport VkViewport where
  withVk (Viewport x y w h mi ma) fn =
    (wrapValue x $
     wrapValue y $
     wrapValue w $
     wrapValue h $
     wrapValue mi $
     wrapValue ma fn)
    VkViewport

data PipelineViewportStateCreateInfo = PipelineViewportStateCreateInfo
                                   { flags :: PipelineViewportStateCreateFlags
                                   , viewports :: [Viewport]
                                   , scissors :: [Rect2D]
                                   }
  deriving (Eq, Ord, Show)

instance WithVk PipelineViewportStateCreateInfo VkPipelineViewportStateCreateInfo where
  withVk (PipelineViewportStateCreateInfo f v s) fn =
    (wrapValue f $ wrapInArray v $ wrapInArray s fn)
    (VkPipelineViewportStateCreateInfo VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO nullPtr)

type PipelineRasterizationStateCreateFlags = Flags VkPipelineRasterizationStateCreateFlags

type PolygonMode = Enumerator VkPolygonMode

type CullModeFlags = Flags VkCullModeFlags

type FrontFace = Enumerator VkFrontFace

data PipelineRasterizationStateCreateInfo = PipelineRasterizationStateCreateInfo
                                            { flags :: PipelineRasterizationStateCreateFlags
                                            , depthClampEnable :: Bool
                                            , rasterizerDiscardEnable :: Bool
                                            , polygonMode :: PolygonMode
                                            , cullMode :: CullModeFlags
                                            , frontFace :: FrontFace
                                            , depthBiasEnable :: Bool
                                            , depthBiasConstantFactor :: Float
                                            , depthBiasClamp :: Float
                                            , depthBiasSlopeFactor :: Float
                                            , lineWidth :: Float
                                            }
                                          deriving (Eq, Ord, Show)

instance WithVk PipelineRasterizationStateCreateInfo VkPipelineRasterizationStateCreateInfo where
  withVk (PipelineRasterizationStateCreateInfo f dce rde pm cm ff dbe dbcf dbc dbsf lw) fn =
    (wrapValue f $
     wrapValue dce $
     wrapValue rde $
     wrapValue pm $
     wrapValue cm $
     wrapValue ff $
     wrapValue dbe $
     wrapValue dbcf $
     wrapValue dbc $
     wrapValue dbsf $
     wrapValue lw fn)
    (VkPipelineRasterizationStateCreateInfo VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO nullPtr)

type PipelineMultisampleStateCreateFlags = Flags VkPipelineMultisampleStateCreateFlags

newtype SampleMask = SampleMask Word
                   deriving (Eq, Ord, Show)

instance WithVk SampleMask VkSampleMask where
  withVk (SampleMask m) fn =
    (wrapValue m fn)
    VkSampleMask

data PipelineMultisampleStateCreateInfo = PipelineMultisampleStateCreateInfo
                                          { flags :: PipelineMultisampleStateCreateFlags
                                          , rasterizationSamples :: SampleCountFlags
                                          , sampleShadingEnable :: Bool
                                          , minSampleShading :: Float
                                          , sampleMask :: Maybe [SampleMask]
                                          , alphaToCoverageEnable :: Bool
                                          , alphaToOneEnable :: Bool
                                          }
                                        deriving (Eq, Ord, Show)

instance WithVk PipelineMultisampleStateCreateInfo VkPipelineMultisampleStateCreateInfo where
  withVk (PipelineMultisampleStateCreateInfo f rs sse mss sm atce atoe) fn =
    (wrapValue f $
     wrapValue rs $
     wrapValue sse $
     wrapValue mss $
     wrapOptArrayNoCount sm $
     wrapValue atce $
     wrapValue atoe fn)
    (VkPipelineMultisampleStateCreateInfo VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO nullPtr)

type PipelineDepthStencilStateCreateFlags = Flags VkPipelineDepthStencilStateCreateFlags

type StencilOp = Enumerator VkStencilOp

type CompareOp = Enumerator VkCompareOp

data StencilOpState = StencilOpState { failOp :: StencilOp
                                     , passOp :: StencilOp
                                     , depthFailOp :: StencilOp
                                     , compareOp :: CompareOp
                                     , compareMask :: Word
                                     , writeMask :: Word
                                     , reference :: Word
                                     }
                    deriving (Eq, Ord, Show)

instance WithVk StencilOpState VkStencilOpState where
  withVk (StencilOpState fo po dfo co cm wm r) fn =
    (wrapValue fo $
     wrapValue po $
     wrapValue dfo $
     wrapValue co $
     wrapValue cm $
     wrapValue wm $
     wrapValue r fn)
    VkStencilOpState

data PipelineDepthStencilStateCreateInfo = PipelineDepthStencilStateCreateInfo
                                           { flags :: PipelineDepthStencilStateCreateFlags
                                           , depthTestEnable :: Bool
                                           , depthWriteEnable :: Bool
                                           , depthCompareOp :: CompareOp
                                           , depthBoundsTestEnable :: Bool
                                           , stencilTestEnable :: Bool
                                           , front :: StencilOpState
                                           , back :: StencilOpState
                                           , minDepthBounds :: Float
                                           , maxDepthBounds :: Float
                                           }
                                         deriving (Eq, Ord, Show)

instance WithVk PipelineDepthStencilStateCreateInfo VkPipelineDepthStencilStateCreateInfo where
  withVk (PipelineDepthStencilStateCreateInfo fl dte dwe dco dbte ste f b midb madb) fn =
    (wrapValue fl $
     wrapValue dte $
     wrapValue dwe $
     wrapValue dco $
     wrapValue dbte $
     wrapValue ste $
     wrapValue f $
     wrapValue b $
     wrapValue midb $
     wrapValue madb fn)
    (VkPipelineDepthStencilStateCreateInfo VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO nullPtr)

type PipelineColorBlendStateCreateFlags = Flags VkPipelineColorBlendStateCreateFlags

type LogicOp = Enumerator VkLogicOp

type BlendFactor = Enumerator VkBlendFactor

type BlendOp = Enumerator VkBlendOp

type ColorComponentFlags = Flags VkColorComponentFlags

data PipelineColorBlendAttachmentState = PipelineColorBlendAttachmentState
                                         { blendEnable :: Bool
                                         , srcColorBlendFactor :: BlendFactor
                                         , dstColorBlendFactor :: BlendFactor
                                         , colorBlendOp :: BlendOp
                                         , srcAlphaBlendFactor :: BlendFactor
                                         , dstAlphaBlendFactor :: BlendFactor
                                         , alphaBlendOp :: BlendOp
                                         , colorWriteMask :: ColorComponentFlags
                                         }
                                       deriving (Eq, Ord, Show)

instance WithVk PipelineColorBlendAttachmentState VkPipelineColorBlendAttachmentState where
  withVk (PipelineColorBlendAttachmentState be scbf dcbf cbo sabf dabf abo cwm) fn =
    (wrapValue be $
     wrapValue scbf $
     wrapValue dcbf $
     wrapValue cbo $
     wrapValue sabf $
     wrapValue dabf $
     wrapValue abo $
     wrapValue cwm fn)
    VkPipelineColorBlendAttachmentState

data PipelineColorBlendStateCreateInfo = PipelineColorBlendStateCreateInfo
                                         { flags :: PipelineColorBlendStateCreateFlags
                                         , logicOpEnable :: Bool
                                         , logicOp :: LogicOp
                                         , attachments :: [PipelineColorBlendAttachmentState]
                                         -- TODO Vector
                                         , blendConstants :: Vector 4 CFloat
                                         }
                                       deriving (Eq, Ord, Show)

instance WithVk PipelineColorBlendStateCreateInfo VkPipelineColorBlendStateCreateInfo where
  withVk (PipelineColorBlendStateCreateInfo f loe lo a bc) fn =
    (wrapValue f $
     wrapValue loe $
     wrapValue lo $
     wrapInArray a $
     wrapConst bc fn)
    (VkPipelineColorBlendStateCreateInfo VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO nullPtr)

type PipelineDynamicStateCreateFlags = Flags VkPipelineDynamicStateCreateFlags

type DynamicState = Enumerator VkDynamicState

data PipelineDynamicStateCreateInfo = PipelineDynamicStateCreateInfo
                                      { flags :: PipelineDynamicStateCreateFlags
                                      , dynamicStates :: [DynamicState]
                                      }
  deriving (Eq, Ord, Show)

instance WithVk PipelineDynamicStateCreateInfo VkPipelineDynamicStateCreateInfo where
  withVk (PipelineDynamicStateCreateInfo f ds) fn =
    (wrapValue f $
     wrapInArray ds fn)
    (VkPipelineDynamicStateCreateInfo VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO nullPtr)

type PipelineLayout = Handle VkPipelineLayout

data GraphicsPipelineCreateInfo = GraphicsPipelineCreateInfo { flags :: PipelineCreateFlags
                                                             , stages :: [PipelineShaderStageCreateInfo]
                                                             , vertexInputState :: PipelineVertexInputStateCreateInfo
                                                             , inputAssemblyState :: PipelineInputAssemblyStateCreateInfo
                                                             , tessellationState :: Maybe PipelineTessellationStateCreateInfo
                                                             -- TODO: Combine null on raster states
                                                             , viewportState :: Maybe PipelineViewportStateCreateInfo
                                                             , rasterizationState :: PipelineRasterizationStateCreateInfo
                                                             , multisampleState :: Maybe PipelineMultisampleStateCreateInfo
                                                             , depthStencilState :: PipelineDepthStencilStateCreateInfo
                                                             , colorBlendState :: PipelineColorBlendStateCreateInfo
                                                             , dynamicState :: Maybe PipelineDynamicStateCreateInfo
                                                             , layout :: PipelineLayout
                                                             , renderPass :: RenderPass
                                                             , subpass :: Word
                                                             -- TODO: Either or, depends on flags
                                                             , basePipelineHandle :: Pipeline
                                                             , basePipelineIndex :: Int
                                                             }

instance WithVk GraphicsPipelineCreateInfo VkGraphicsPipelineCreateInfo where
  withVk (GraphicsPipelineCreateInfo f s vis ias ts vs rs ms dss cbs ds l rp sp bph bpi) fn =
    (wrapValue f $
     wrapInArray s $
     wrapInPtr vis $
     wrapInPtr ias $
     wrapOptPtr ts $
     wrapOptPtr vs $
     wrapInPtr rs $
     wrapOptPtr ms $
     wrapInPtr dss $
     wrapInPtr cbs $
     wrapOptPtr ds $
     wrapValue l $
     wrapValue rp $
     wrapValue sp $
     wrapValue bph $
     wrapValue bpi fn)
    (VkGraphicsPipelineCreateInfo VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO nullPtr)

type Pipeline = Handle VkPipeline

createGraphicsPipelines :: Device -> [GraphicsPipelineCreateInfo] -> IO [Pipeline]
createGraphicsPipelines d ci =
  (wrapValue d $
   wrapConst (VkPipelineCache 0) $
   wrapInArray ci $
   wrapConst nullPtr $
   wrapOutArray (fromIntegral $ length ci) id)
  vkCreateGraphicsPipelines

createGraphicsPipeline :: Device -> GraphicsPipelineCreateInfo -> IO Pipeline
createGraphicsPipeline d ci = head <$> createGraphicsPipelines d [ci]
